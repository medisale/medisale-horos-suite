#import "HorosAdapter.h"

#import "ImageContext.h"
#import <DCMPix.h>
#import <DCMView.h>
#import <DicomImage.h>
#import <DicomSeries.h>
#import <DicomStudy.h>
#import <ViewerController.h>

@implementation HorosAdapter

+ (ImageContext *)imageContextForViewer:(ViewerController *)viewer error:(NSError **)error
{
    DicomImage *image = [viewer currentImage];
    DCMPix *pix = viewer.imageView.curDCM;
    NSString *studyUID = image.series.study.studyInstanceUID;
    NSString *seriesUID = image.series.seriesDICOMUID;
    NSString *sopUID = [image sopInstanceUID];

    if (image == nil || pix == nil || studyUID.length == 0 ||
        seriesUID.length == 0 || sopUID.length == 0 ||
        pix.pwidth <= 0 || pix.pheight <= 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"jp.medisale.horos-adapter"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"The current Horos image does not expose a complete context."}];
        }
        return nil;
    }

    return [[ImageContext alloc] initWithStudyInstanceUID:studyUID
                                        seriesInstanceUID:seriesUID
                                           sopInstanceUID:sopUID
                                              frameNumber:pix.frameNo
                                               pixelWidth:pix.pwidth
                                              pixelHeight:pix.pheight
                                            pixelSpacingX:pix.pixelSpacingX
                                            pixelSpacingY:pix.pixelSpacingY];
}

@end
