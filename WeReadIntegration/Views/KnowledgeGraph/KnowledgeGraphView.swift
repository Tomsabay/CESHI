// KnowledgeGraphView.swift
// SwiftUI Canvas 知识图谱：将书籍/概念/划线渲染为力导向图
//
// 功能：
//   1. Claude 分析所有划线，提取核心概念节点和书籍间关联边
//   2. 用 Verlet 积分做力导向布局（弹簧 + 斥力 + 阻尼）
//   3. 支持双指缩放、拖拽节点、点击查看划线
//   4. 节点颜色按书籍分组，边宽代表关联强度

import SwiftUI
import Combine

// MARK: - 数据模型

struct GraphNode: Identifiable {
    let id: UUID
    var label: String
    var type: NodeType
    var bookId: String?
    var relatedHighlights: [String]  // 划线文本
    var position: CGPoint
    var velocity: CGPoint = .zero
    var isPinned: Bool = false

    enum NodeType {
        case book(color: Color)
        case concept(color: Color)
    }

    var color: Color {
        switch type {
        case .book(let c): return c
        case .concept(let c): return c
        }
    }

    var radius: CGFloat {
        switch type {
        case .book: return 28
        case .concept: return 18
        }
    }
}

struct GraphEdge: Identifiable {
    let id = UUID()
    let fromId: UUID
    let toId: UUID
    let strength: Double   // 0.0 ~ 1.0，越高连线越粗
    let label: String?     // 关联描述
}

// MARK: - 力导向布局引擎

@MainActor
final class ForceDirectedLayout: ObservableObject {
    @Published var nodes: [GraphNode] = []
    @Published var edges: [GraphEdge] = []

    private var displayLink: CADisplayLink?
    private let damping: CGFloat = 0.85
    private let repulsion: CGFloat = 3000
    private let springLength: CGFloat = 120
    private let springK: CGFloat = 0.08

    var canvasSize: CGSize = CGSize(width: 400, height: 600)

    func startSimulation() {
        stopSimulation()
        let dl = CADisplayLink(target: self, selector: #selector(step))
        dl.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        dl.add(to: .main, forMode: .common)
        displayLink = dl
    }

    func stopSimulation() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step() {
        guard !nodes.isEmpty else { return }

        // 计算力
        var forces = [UUID: CGPoint]()
        for node in nodes { forces[node.id] = .zero }

        // 节点间斥力
        for i in 0..<nodes.count {
            for j in (i + 1)..<nodes.count {
                let dx = nodes[j].position.x - nodes[i].position.x
                let dy = nodes[j].position.y - nodes[i].position.y
                let dist = max(sqrt(dx * dx + dy * dy), 1)
                let force = repulsion / (dist * dist)
                let fx = force * dx / dist
                let fy = force * dy / dist
                forces[nodes[i].id]!.x -= fx
                forces[nodes[i].id]!.y -= fy
                forces[nodes[j].id]!.x += fx
                forces[nodes[j].id]!.y += fy
            }
        }

        // 弹簧引力（边）
        let nodeMap = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        for edge in edges {
            guard let a = nodeMap[edge.fromId], let b = nodeMap[edge.toId] else { continue }
            let dx = b.position.x - a.position.x
            let dy = b.position.y - a.position.y
            let dist = max(sqrt(dx * dx + dy * dy), 1)
            let displacement = dist - springLength * (1 + (1 - edge.strength))
            let force = springK * displacement
            let fx = force * dx / dist
            let fy = force * dy / dist
            forces[edge.fromId]!.x += fx
            forces[edge.fromId]!.y += fy
            forces[edge.toId]!.x -= fx
            forces[edge.toId]!.y -= fy
        }

        // 中心引力（防止图散开）
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        for node in nodes {
            let dx = center.x - node.position.x
            let dy = center.y - node.position.y
            forces[node.id]!.x += dx * 0.01
            forces[node.id]!.y += dy * 0.01
        }

        // 更新速度和位置（Verlet 积分）
        for i in 0..<nodes.count {
            guard !nodes[i].isPinned else { continue }
            nodes[i].velocity.x = (nodes[i].velocity.x + forces[nodes[i].id]!.x) * damping
            nodes[i].velocity.y = (nodes[i].velocity.y + forces[nodes[i].id]!.y) * damping
            nodes[i].position.x = max(50, min(canvasSize.width - 50,
                                              nodes[i].position.x + nodes[i].velocity.x * 0.016))
            nodes[i].position.y = max(50, min(canvasSize.height - 50,
                                              nodes[i].position.y + nodes[i].velocity.y * 0.016))
        }
    }
}

// MARK: - 图谱构建器（Claude 提取概念）

@MainActor
final class KnowledgeGraphBuilder: ObservableObject {
    @Published var layout = ForceDirectedLayout()
    @Published var isBuilding = false
    @Published var selectedNode: GraphNode?
    @Published var buildProgress: String = ""

    private let bookColors: [Color] = [
        .blue, .green, .orange, .purple, .pink, .teal, .red, .indigo
    ]

    func build(from userData: WeReadUserData, canvasSize: CGSize) async {
        isBuilding = true
        layout.canvasSize = canvasSize
        layout.stopSimulation()

        buildProgress = "正在提取概念节点..."

        // 向 Claude 提取概念
        let graphData = await extractGraphFromClaude(userData: userData)

        buildProgress = "构建图谱结构..."

        // 创建书籍节点
        var nodes: [GraphNode] = []
        var edges: [GraphEdge] = []
        var bookNodeMap: [String: UUID] = [:]

        let usedBooks = Set(userData.highlights.map { $0.bookId })
        let books = userData.books.filter { usedBooks.contains($0.bookId) }.prefix(12)

        for (idx, book) in books.enumerated() {
            let color = bookColors[idx % bookColors.count]
            let angle = CGFloat(idx) / CGFloat(books.count) * .pi * 2
            let r = min(canvasSize.width, canvasSize.height) * 0.28
            let node = GraphNode(
                id: UUID(),
                label: shortenTitle(book.title),
                type: .book(color: color),
                bookId: book.bookId,
                relatedHighlights: userData.highlights
                    .filter { $0.bookId == book.bookId }
                    .map { $0.markText },
                position: CGPoint(
                    x: canvasSize.width / 2 + r * cos(angle),
                    y: canvasSize.height / 2 + r * sin(angle)
                )
            )
            nodes.append(node)
            bookNodeMap[book.bookId] = node.id
        }

        // 创建概念节点（来自 Claude）
        var conceptNodeMap: [String: UUID] = [:]
        for concept in graphData.concepts.prefix(20) {
            let node = GraphNode(
                id: UUID(),
                label: concept.name,
                type: .concept(color: .yellow),
                relatedHighlights: concept.relatedHighlights,
                position: CGPoint(
                    x: CGFloat.random(in: 80...(canvasSize.width - 80)),
                    y: CGFloat.random(in: 80...(canvasSize.height - 80))
                )
            )
            nodes.append(node)
            conceptNodeMap[concept.name] = node.id
        }

        // 创建边：书籍 ↔ 概念
        for link in graphData.links {
            let fromId = bookNodeMap[link.bookId] ?? conceptNodeMap[link.fromConcept ?? ""]
            let toId = conceptNodeMap[link.toConcept]
            if let f = fromId, let t = toId {
                edges.append(GraphEdge(
                    fromId: f, toId: t,
                    strength: link.strength,
                    label: link.relation
                ))
            }
        }

        // 书籍之间的强关联边
        for edge in graphData.bookLinks {
            if let f = bookNodeMap[edge.bookIdA], let t = bookNodeMap[edge.bookIdB] {
                edges.append(GraphEdge(fromId: f, toId: t, strength: edge.strength, label: edge.relation))
            }
        }

        layout.nodes = nodes
        layout.edges = edges
        isBuilding = false
        buildProgress = ""
        layout.startSimulation()
    }

    private func shortenTitle(_ title: String) -> String {
        let cleaned = title.replacingOccurrences(of: "《", with: "").replacingOccurrences(of: "》", with: "")
        return cleaned.count > 6 ? String(cleaned.prefix(6)) + "…" : cleaned
    }

    // MARK: - Claude 提取图谱数据

    struct GraphData {
        struct Concept {
            let name: String
            let relatedHighlights: [String]
        }
        struct Link {
            let bookId: String?
            let fromConcept: String?
            let toConcept: String
            let strength: Double
            let relation: String
        }
        struct BookLink {
            let bookIdA: String
            let bookIdB: String
            let strength: Double
            let relation: String
        }

        let concepts: [Concept]
        let links: [Link]
        let bookLinks: [BookLink]
    }

    private func extractGraphFromClaude(userData: WeReadUserData) async -> GraphData {
        guard let apiKey = KeychainHelper.shared.getString(
            service: "com.anthropic.claudeapp", key: "api_key") else {
            return GraphData(concepts: [], links: [], bookLinks: [])
        }

        let highlightSample = userData.highlights.prefix(80).map { h in
            let book = userData.books.first { $0.bookId == h.bookId }
            return "《\(book?.title ?? "未知")》: \(h.markText)"
        }.joined(separator: "\n")

        let prompt = """
        请分析以下划线，提取知识图谱，返回 JSON：

        \(highlightSample)

        返回格式：
        {
          "concepts": [{"name": "专注力", "highlights": ["划线1", "划线2"]}],
          "bookConceptLinks": [{"bookTitle": "深度工作", "concept": "专注力", "strength": 0.9, "relation": "核心论述"}],
          "bookLinks": [{"bookA": "深度工作", "bookB": "心流", "strength": 0.85, "relation": "都关注专注与心流"}]
        }
        concepts 最多 15 个，bookLinks 最多 10 个，只返回 JSON。
        """

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            return GraphData(concepts: [], links: [], bookLinks: [])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 2048,
            "messages": [["role": "user", "content": prompt]]
        ])

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = (json["content"] as? [[String: Any]])?.first?["text"] as? String else {
            return GraphData(concepts: [], links: [], bookLinks: [])
        }

        // 解析 JSON
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let d = cleaned.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            return GraphData(concepts: [], links: [], bookLinks: [])
        }

        let concepts = (obj["concepts"] as? [[String: Any]] ?? []).map { c in
            GraphData.Concept(
                name: c["name"] as? String ?? "",
                relatedHighlights: c["highlights"] as? [String] ?? []
            )
        }

        let bookTitleToId = Dictionary(
            uniqueKeysWithValues: userData.books.map { ($0.title.replacingOccurrences(of: "《", with: "").replacingOccurrences(of: "》", with: ""), $0.bookId) }
        )

        let links = (obj["bookConceptLinks"] as? [[String: Any]] ?? []).compactMap { l -> GraphData.Link? in
            let bookTitle = l["bookTitle"] as? String ?? ""
            let bookId = bookTitleToId[bookTitle]
            return GraphData.Link(
                bookId: bookId,
                fromConcept: nil,
                toConcept: l["concept"] as? String ?? "",
                strength: l["strength"] as? Double ?? 0.5,
                relation: l["relation"] as? String ?? ""
            )
        }

        let bookLinks = (obj["bookLinks"] as? [[String: Any]] ?? []).compactMap { l -> GraphData.BookLink? in
            guard let idA = bookTitleToId[l["bookA"] as? String ?? ""],
                  let idB = bookTitleToId[l["bookB"] as? String ?? ""] else { return nil }
            return GraphData.BookLink(
                bookIdA: idA, bookIdB: idB,
                strength: l["strength"] as? Double ?? 0.5,
                relation: l["relation"] as? String ?? ""
            )
        }

        return GraphData(concepts: concepts, links: links, bookLinks: bookLinks)
    }
}

// MARK: - 主 View

struct KnowledgeGraphView: View {
    let userData: WeReadUserData
    @StateObject private var builder = KnowledgeGraphBuilder()
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    @State private var showNodeDetail = false
    @State private var draggedNodeId: UUID?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 背景
                Color(hex: "#0d1117").ignoresSafeArea()

                if builder.isBuilding {
                    buildingView
                } else {
                    // 图谱画布
                    Canvas { ctx, size in
                        drawGraph(ctx: ctx, size: size)
                    }
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(magnificationGesture)
                    .gesture(dragGesture)
                    .onAppear {
                        builder.layout.canvasSize = geo.size
                    }

                    // 节点标签层（Canvas 不支持交互，用 overlay）
                    nodeLabelsOverlay
                        .scaleEffect(scale)
                        .offset(offset)

                    // 控制栏
                    controlBar
                        .padding()
                }
            }
            .onAppear {
                Task {
                    await builder.build(from: userData, canvasSize: geo.size)
                }
            }
        }
        .navigationTitle("知识图谱")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showNodeDetail) {
            if let node = builder.selectedNode {
                NodeDetailSheet(node: node)
            }
        }
    }

    // MARK: - Canvas 绘图

    private func drawGraph(ctx: GraphicsContext, size: CGSize) {
        let nodeMap = Dictionary(uniqueKeysWithValues: builder.layout.nodes.map { ($0.id, $0) })

        // 绘制边
        for edge in builder.layout.edges {
            guard let from = nodeMap[edge.fromId],
                  let to = nodeMap[edge.toId] else { continue }

            var path = Path()
            path.move(to: from.position)
            path.addLine(to: to.position)

            ctx.stroke(path, with: .color(.white.opacity(0.15 + edge.strength * 0.25)),
                       lineWidth: CGFloat(0.5 + edge.strength * 2))
        }

        // 绘制节点
        for node in builder.layout.nodes {
            let r = node.radius
            let rect = CGRect(x: node.position.x - r, y: node.position.y - r,
                              width: r * 2, height: r * 2)

            // 发光效果
            ctx.fill(Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)),
                     with: .color(node.color.opacity(0.2)))
            // 主圆
            ctx.fill(Path(ellipseIn: rect), with: .color(node.color))
            // 描边
            ctx.stroke(Path(ellipseIn: rect),
                       with: .color(.white.opacity(0.4)), lineWidth: 1.5)
        }
    }

    // MARK: - 节点标签（可交互 overlay）

    private var nodeLabelsOverlay: some View {
        ZStack {
            ForEach(builder.layout.nodes) { node in
                Button {
                    builder.selectedNode = node
                    showNodeDetail = true
                } label: {
                    VStack(spacing: 2) {
                        Circle()
                            .fill(node.color.opacity(0.001)) // 透明热区
                            .frame(width: node.radius * 2, height: node.radius * 2)
                        Text(node.label)
                            .font(.system(size: node.type == .book(color: .clear) ? 10 : 9,
                                          weight: .medium))
                            .foregroundColor(.white)
                            .shadow(color: .black, radius: 2)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(width: 64)
                    }
                }
                .position(node.position)
            }
        }
    }

    // MARK: - 手势

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { v in scale = max(0.3, min(4, lastScale * v)) }
            .onEnded { _ in lastScale = scale }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { v in offset = CGSize(
                width: offset.width + v.translation.width,
                height: offset.height + v.translation.height
            )}
            .onEnded { _ in }
    }

    // MARK: - 控制栏

    private var controlBar: some View {
        VStack {
            Spacer()
            HStack {
                Button {
                    withAnimation { scale = 1; offset = .zero }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.bottom.right")
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .cornerRadius(10)
                }

                Spacer()

                Text("\(builder.layout.nodes.count) 节点 · \(builder.layout.edges.count) 关联")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
            }
        }
    }

    // MARK: - 构建中视图

    private var buildingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
            Text(builder.buildProgress)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
        }
    }
}

// MARK: - 节点详情 Sheet

struct NodeDetailSheet: View {
    let node: GraphNode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Circle().fill(node.color).frame(width: 24, height: 24)
                        Text(node.label).font(.headline)
                    }
                }

                if !node.relatedHighlights.isEmpty {
                    Section("相关划线（\(node.relatedHighlights.count) 条）") {
                        ForEach(node.relatedHighlights.prefix(10), id: \.self) { text in
                            Text(text)
                                .font(.body)
                                .padding(8)
                                .background(.yellow.opacity(0.1))
                                .cornerRadius(6)
                                .listRowSeparator(.hidden)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("节点详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Color helper (局部)
private extension Color {
    static func == (lhs: Color, rhs: Color) -> Bool { false }
    init(hex: String) {
        let s = Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")))
        var v: UInt64 = 0; s.scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}

// NodeType Equatable for color comparison
extension GraphNode.NodeType: Equatable {
    static func == (lhs: GraphNode.NodeType, rhs: GraphNode.NodeType) -> Bool {
        switch (lhs, rhs) {
        case (.book, .book): return true
        case (.concept, .concept): return true
        default: return false
        }
    }
}
