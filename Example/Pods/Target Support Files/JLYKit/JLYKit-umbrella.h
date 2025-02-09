#ifdef __OBJC__
#import <UIKit/UIKit.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import "JLYAppDelegate+Method.h"
#import "JLYAppDelegate.h"
#import "JLYAppServiceManager.h"
#import "JLYAppUtils.h"
#import "JLYAvatarBrowser.h"
#import "JLYLocation.h"
#import "JLYPanAnimationController.h"
#import "JLYReversibleAnimationController.h"
#import "viewControllerConfig.h"
#import "NSData+imageWrite.h"
#import "NSDate+JLYExtension.h"
#import "NSNull+NullSafe.h"
#import "NSNumber+numToString.h"
#import "NSObject+DateString.h"
#import "NSObject+JsonString.h"
#import "NSObject+Path.h"
#import "NSString+JLYDecimal.h"
#import "NSString+JLYRegExKit.h"
#import "NSString+JLY_CalculateSize.h"
#import "NSString+MD5Addition.h"
#import "JLYMethodSwizzling.h"
#import "UIButton+animation.h"
#import "UIButton+center.h"
#import "UIButton+JLYSubmitting.h"
#import "JLYBaseTableViewCell.h"
#import "JLYBaseTableViewHeaderFooterView.h"
#import "JLYBaseTableViewDataSource.h"
#import "JLYDataSourceSection.h"
#import "JLYTableViewDataSource.h"
#import "JLYTableViewDataSourceMaker.h"
#import "JLYTableViewSectionMaker.h"
#import "UITableView+JLYTableViewDataSource.h"
#import "JLYBaseTableViewController.h"
#import "JLYBaseViewController.h"
#import "JLYBaseViewModel.h"
#import "JLYLaunchAnimationProtocol.h"
#import "JLYLaunchBaseAnimation.h"
#import "JLYLaunchFadeScaleAnimation.h"
#import "UIImage+JLYLaunchImage.h"
#import "UIView+JLYLaunchAnimation.h"
#import "JLYCommonParamsGenerator.h"
#import "JLYRequestGenerator.h"
#import "JLYSignatureGenerator.h"
#import "JLYUDIDGenerator.h"
#import "JLYCache.h"
#import "JLYCachedObject.h"
#import "JLYApiProxy.h"
#import "JLYAppContext.h"
#import "JLYURLResponse.h"
#import "JLYLogger.h"
#import "JLYLoggerConfiguration.h"
#import "AFHTTPSessionOperation.h"
#import "AFURLSessionOperation.h"
#import "AsynchronousOperation.h"
#import "NSArray+JLYNetworkingMethods.h"
#import "NSDictionary+JLYNetworkingMethods.h"
#import "NSMutableString+JLYNetworkingMethods.h"
#import "NSObject+JLYNetworkingMethods.h"
#import "NSString+JLYNetworkingMethods.h"
#import "NSURLRequest+JLYNetworkingMethods.h"
#import "UIDevice+identifierAddition.h"
#import "JLYAPIBaseManager.h"
#import "JLYNetworking.h"
#import "JLYNetworkingConfiguration.h"
#import "JLYService.h"
#import "JLYServiceFactory.h"
#import "JLYSqliteWithModel.h"
#import "JLYURLRouter.h"
#import "JLYBaseDAO.h"
#import "JLYBaseInteractor.h"
#import "JLYBaseInteractorIO.h"
#import "JLYBasePresenter.h"
#import "JLYBaseRouter.h"
#import "JLYBaseVCModuleProtocol.h"
#import "JLYVIPERMacro.h"
#import "UIViewController+JLYVIPER.h"
#import "UIColor+HexColors.h"
#import "UIControl+JLYFixMultiClick.h"
#import "UIImage+colorImage.h"
#import "UIImage+HEIC.h"
#import "UIImage+Transform.h"
#import "UIImageView+JLYAdditions.h"
#import "UINavigationBar+Awesome.h"
#import "UINavigationController+JLYStackManager.h"
#import "UIScrollView+EmptyDataSet.h"
#import "UITextView+JLYPlaceHolder.h"
#import "UITextView+JLYSelect.h"
#import "UIView+Additions.h"
#import "JLYBaseNavigationController.h"
#import "UIViewController+JLYAdditions.h"
#import "UIViewController+JLYNavSafeTransation.h"
#import "JLYAlertAction.h"
#import "JLYAlertController.h"
#import "JLYCountDownButton.h"
#import "JLYDatePickerView.h"
#import "JLYForm.h"
#import "JLYGrowingTextView.h"
#import "JLYLoadingShimmer.h"
#import "JLYDottedLineLayer.h"
#import "JLYFloatTextField.h"
#import "JLYFloatTextView.h"
#import "JLYMaterialTextFeild.h"
#import "JLYMaterialTextView.h"
#import "NSString+TextDirectionality.h"
#import "JLYNavigationSubtitleView.h"
#import "JLYPopMenuModel.h"
#import "JLYPopMenuTableViewCell.h"
#import "JLYPopMenuView.h"
#import "JLYSegmentControl.h"
#import "RMActionController.h"
#import "RMDateSelectionViewController.h"
#import "NSObject+YYModel.h"
#import "YYClassInfo.h"
#import "YYModel.h"

FOUNDATION_EXPORT double JLYKitVersionNumber;
FOUNDATION_EXPORT const unsigned char JLYKitVersionString[];

