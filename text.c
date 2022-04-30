#define _CRT_SECURE_NO_WARNINGS 1

#include <stdio.h>

//int main()//主函数-程序的入口
//{
	//这里完成任务
	//在屏幕上打印
	//函数 -print function-printf 此为库函数
	//#include <stdio.h>-包含一个叫stdio.h的文件 别人的东西要打招呼

	//printf("hellow 李娜\n");
	//printf("hello world\n"); 
	//return 0;//返回 0
//}

//int是整型的意思 从主函数中返回一个整型值
// \n是换行的意思

//int num1 = 10;//定义在代码块之外的变量是全局变量，局部变量和全局变量先执行局部变量，二者的名字建议不要相同，
//容易产生bug，局部变量只能在大括号内起作用
//int main()
//{
	// char ch = 'A';//申请内存ch存储A
	// printf("%c\n",ch);//以字符格式打印A
	
	//int age = 2000000;
	//printf("%d\n",age);//%d表示打印整型十进制数据
	
	//long num = 100;//长整型
	//printf("%d\n", num);
	
	//float f = 5.0;
	//printf("%f\n", f);
	

	//double d = 3.14;
	//printf("%lf\n", d);
	//return 0;

	//printf("%d\n", sizeof(char));//1个字节
	//printf("%d\n", sizeof(short));//2
	//printf("%d\n", sizeof(int));//4个字节 =32bit  可表示2的三十二次方减一的范围
	//printf("%d\n", sizeof(long));//4/8
	//printf("%d\n", sizeof(long long));//8
	//printf("%d\n", sizeof(float));//4
	//printf("%d\n", sizeof(double));//8


//}
	//%d打印整型  %c打印字符   %f打印浮点数字  打印小数 

//相加函数
/*



int main()
{
	int num1 = 0;
	//c中定义变量必须在代码块 最前面
	int num2 = 0;
	int sum = 0;
	scanf("%d%d", &num1, &num2);//scanf输入数据使用的输入函数，&取地址符号
	
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
	printf("请输入三个整数:");
	scanf("%d%d%d",&x,&y,&z);
	if (x > y)
		result = y;
	else
		result = x;
	if (result > z)
		result = z;
	else
		printf("最小值为：%d\n", result);
	printf("最小值为：%d\n", result);
	return 0;
}
int main()
{
	printf("*****************************\n");
	printf("      一分耕耘，一分收获     \n");
	printf("*****************************\n");
	return 0;
}






