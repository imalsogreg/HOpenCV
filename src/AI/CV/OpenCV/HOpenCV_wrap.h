#include <cv.h>


void release_capture(CvCapture *capture);

    
void new_window(int num, int flags);
void del_window(int num);
void show_image(int num, IplImage *image);
/*void dilate(IplImage *src, int iterations, IplImage *dest);*/
