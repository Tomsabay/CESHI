#define _CRT_SECURE_NO_WARNINGS 1

#include <stdio.h>

//int main()//������-��������
//{
	//�����������
	//����Ļ�ϴ�ӡ
	//���� -print function-printf ��Ϊ�⺯��
	//#include <stdio.h>-����һ����stdio.h���ļ� ���˵Ķ���Ҫ���к�

	//printf("hellow ����\n");
	//printf("hello world\n"); 
	//return 0;//���� 0
//}

//int�����͵���˼ ���������з���һ������ֵ
// \n�ǻ��е���˼

//int num1 = 10;//�����ڴ����֮��ı�����ȫ�ֱ������ֲ�������ȫ�ֱ�����ִ�оֲ����������ߵ����ֽ��鲻Ҫ��ͬ��
//���ײ���bug���ֲ�����ֻ���ڴ�������������
//int main()
//{
	// char ch = 'A';//�����ڴ�ch�洢A
	// printf("%c\n",ch);//���ַ���ʽ��ӡA
	
	//int age = 2000000;
	//printf("%d\n",age);//%d��ʾ��ӡ����ʮ��������
	
	//long num = 100;//������
	//printf("%d\n", num);
	
	//float f = 5.0;
	//printf("%f\n", f);
	

	//double d = 3.14;
	//printf("%lf\n", d);
	//return 0;

	//printf("%d\n", sizeof(char));//1���ֽ�
	//printf("%d\n", sizeof(short));//2
	//printf("%d\n", sizeof(int));//4���ֽ� =32bit  �ɱ�ʾ2����ʮ���η���һ�ķ�Χ
	//printf("%d\n", sizeof(long));//4/8
	//printf("%d\n", sizeof(long long));//8
	//printf("%d\n", sizeof(float));//4
	//printf("%d\n", sizeof(double));//8


//}
	//%d��ӡ����  %c��ӡ�ַ�   %f��ӡ��������  ��ӡС�� 

//��Ӻ���
/*



int main()
{
	int num1 = 0;
	//c�ж�����������ڴ���� ��ǰ��
	int num2 = 0;
	int sum = 0;
	scanf("%d%d", &num1, &num2);//scanf��������ʹ�õ����뺯����&ȡ��ַ����
	
	sum = num1 + num2;
	printf("sum = %d\n",sum);
	return 0;

	}

	*/

//int main()
//{
//	int x, y,z;
//	x = 10;
//	y = 8;
//	if (x > y)
//		z = x;
//	else
//		z = y;
//	printf("%d\n", z);
//
//
//}
int main()
{
	int x, y,z,result;
	printf("��������������:");
	scanf("%d%d%d",&x,&y,&z);
	if (x > y)
		result = y;
	else
		result = x;
	if (result > z)
		result = z;
	else
		printf("��СֵΪ��%d\n", result);
	printf("��СֵΪ��%d\n", result);
	return 0;
}
int main()
{
	printf("*****************************\n");
	printf("      һ�ָ��ţ�һ���ջ�     \n");
	printf("*****************************\n");
	return 0;
}






