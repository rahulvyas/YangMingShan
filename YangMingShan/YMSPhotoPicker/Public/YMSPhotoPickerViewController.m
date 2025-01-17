//
//  YMSPhotoPickerViewController.m
//  YangMingShan
//
//  Copyright 2016 Yahoo Inc.
//  Licensed under the terms of the BSD license. Please see LICENSE file in the project root for terms.
//

#import "YMSPhotoPickerViewController.h"

#import <Photos/Photos.h>

#import "UIScrollView+YMSAdditions.h"
#import "UIViewController+YMSPhotoHelper.h"
#import "YMSAlbumPickerViewController.h"
#import "YMSCameraCell.h"
#import "YMSPhotoCell.h"
#import "YMSVideoCell.h"
#import "YMSSingleMediaViewController.h"
#import "YMSSingleMediaTransition.h"

static NSString * const YMSCameraCellNibName = @"YMSCameraCell";
static NSString * const YMSPhotoCellNibName = @"YMSPhotoCell";
static NSString * const YMSVideoCellNibName = @"YMSVideoCell";
static const CGFloat YMSPhotoFetchScaleResizingRatio = 0.75;

@interface YMSPhotoPickerViewController ()<UICollectionViewDataSource, UICollectionViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, PHPhotoLibraryChangeObserver> {
    YMSSingleMediaViewController *_previewViewController;
    YMSSingleMediaTransition *_previewTransition;
}

@property (nonatomic, weak) IBOutlet UINavigationBar *navigationBar;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *navigationBarTopConstraint;
@property (nonatomic, weak) IBOutlet UIView *navigationBarBackgroundView;
@property (nonatomic, weak) IBOutlet UICollectionView *photoCollectionView;
@property (nonatomic, strong) PHImageManager *imageManager;
@property (nonatomic, weak) AVCaptureSession *session;
@property (nonatomic, strong) NSArray *collectionItems;
@property (nonatomic, strong) NSDictionary *currentCollectionItem;
@property (nonatomic, strong) NSMutableArray *selectedPhotos;
@property (nonatomic, strong) UIBarButtonItem *doneItem;
@property (nonatomic, assign) BOOL needToSelectFirstPhoto;
@property (nonatomic, assign) CGSize cellPortraitSize;
@property (nonatomic, assign) CGSize cellLandscapeSize;

- (IBAction)dismiss:(id)sender;
- (IBAction)presentAlbumPickerView:(id)sender;
- (IBAction)finishPickingPhotos:(id)sender;
- (void)updateViewWithCollectionItem:(NSDictionary *)collectionItem;
- (void)refreshPhotoSelection;
- (void)fetchCollections;
- (BOOL)allowsMultipleSelection;
- (BOOL)canAddPhoto;
- (IBAction)presentSinglePhoto:(id)sender;
- (void)setupCellSize;

@end

@implementation YMSPhotoPickerViewController

- (instancetype)init
{
    self = [super initWithNibName:NSStringFromClass(self.class) bundle:[NSBundle bundleForClass:self.class]];
    if (self) {
        self.selectedPhotos = [NSMutableArray array];
        self.numberOfMediaToSelect = 1;
        self.shouldReturnImageForSingleSelection = YES;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    // Set PHCachingImageManager here because you don't know photo album permission is allowed in init function
    self.imageManager = [[PHCachingImageManager alloc] init];

    self.view.tintColor = self.theme.tintColor;

    self.photoCollectionView.delegate = self;
    self.photoCollectionView.dataSource = self;
    
    UINib *cellNib = [UINib nibWithNibName:YMSCameraCellNibName bundle:[NSBundle bundleForClass:YMSCameraCell.class]];
    [self.photoCollectionView registerNib:cellNib forCellWithReuseIdentifier:YMSCameraCellNibName];
    cellNib = [UINib nibWithNibName:YMSPhotoCellNibName bundle:[NSBundle bundleForClass:YMSPhotoCell.class]];
    [self.photoCollectionView registerNib:cellNib forCellWithReuseIdentifier:YMSPhotoCellNibName];
    cellNib = [UINib nibWithNibName:YMSVideoCellNibName bundle:[NSBundle bundleForClass:YMSVideoCell.class]];
    [self.photoCollectionView registerNib:cellNib forCellWithReuseIdentifier:YMSVideoCellNibName];
    self.photoCollectionView.allowsMultipleSelection = self.allowsMultipleSelection;

    [self fetchCollections];

    UINavigationItem *navigationItem = [[UINavigationItem alloc] init];
    navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(dismiss:)];

    if (self.allowsMultipleSelection) {
        // Add done button for multiple selections
        self.doneItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(finishPickingPhotos:)];
        self.doneItem.enabled = NO;
        navigationItem.rightBarButtonItem = self.doneItem;
    }

    self.navigationBar.items = @[navigationItem];

    if (![self.theme.navigationBarBackgroundColor isEqual:[UIColor whiteColor]]) {
        [self.navigationBar setBackgroundImage:[UIImage new] forBarMetrics:UIBarMetricsDefault];
        [self.navigationBar setShadowImage:[UIImage new]];
        self.navigationBarBackgroundView.backgroundColor = self.theme.navigationBarBackgroundColor;
    }
    
    [self updateViewWithCollectionItem:[self.collectionItems firstObject]];

    self.cellPortraitSize = self.cellLandscapeSize = CGSizeZero;
    
    [self adjustStatusBarSpace];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [[PHPhotoLibrary sharedPhotoLibrary] unregisterChangeObserver:self];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id <UIViewControllerTransitionCoordinator>)coordinator
{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [self.photoCollectionView.collectionViewLayout invalidateLayout];
    [self adjustStatusBarSpace];
}

- (void)viewSafeAreaInsetsDidChange
{
    [super viewSafeAreaInsetsDidChange];
    [self setupCellSize];
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return [YMSPhotoPickerTheme sharedInstance].statusBarStyle;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return [YMSPhotoPickerConfiguration sharedInstance].allowedOrientation;
}

#pragma mark - Getters

- (YMSPhotoPickerTheme *)theme
{
    return [YMSPhotoPickerTheme sharedInstance];
}

- (YMSPhotoPickerConfiguration *)configuration
{
    return [YMSPhotoPickerConfiguration sharedInstance];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    // +1 for camera cell
    PHFetchResult *fetchResult = self.currentCollectionItem[@"assets"];
    
    return fetchResult.count + 1;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.row == 0) {   // Camera Cell
        YMSCameraCell *cameraCell = [collectionView dequeueReusableCellWithReuseIdentifier:YMSCameraCellNibName forIndexPath:indexPath];

        self.session = cameraCell.session;
        
        if (![self.session isRunning]) {
            [self.session startRunning];
        }
        
        return cameraCell;
    }
    
    YMSPhotoCell *cell;
    
    PHFetchResult *fetchResult = self.currentCollectionItem[@"assets"];
    PHAsset *asset = fetchResult[indexPath.item-1];
    
    if(asset.mediaType == PHAssetMediaTypeImage) {
        cell = [collectionView dequeueReusableCellWithReuseIdentifier:YMSPhotoCellNibName forIndexPath:indexPath];
    }
    else if(asset.mediaType == PHAssetMediaTypeVideo) {
        cell = [collectionView dequeueReusableCellWithReuseIdentifier:YMSVideoCellNibName forIndexPath:indexPath];
    }

    cell.representedAssetIdentifier = asset.localIdentifier;
    
    CGFloat scale = [UIScreen mainScreen].scale * YMSPhotoFetchScaleResizingRatio;
    CGSize imageSize = CGSizeMake(CGRectGetWidth(cell.frame) * scale, CGRectGetHeight(cell.frame) * scale);
    
    [cell loadPhotoWithManager:self.imageManager forAsset:asset targetSize:imageSize];

    [cell.longPressGestureRecognizer addTarget:self action:@selector(presentSinglePhoto:)];

    if ([self shouldOrderSelection] && [self.selectedPhotos containsObject:asset]) {
        NSUInteger selectionIndex = [self.selectedPhotos indexOfObject:asset];
        cell.selectionOrder = selectionIndex+1;
    }

    return cell;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didHighlightItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView cellForItemAtIndexPath:indexPath];
    if ([cell isKindOfClass:[YMSPhotoCell class]]) {
        [(YMSPhotoCell *)cell animateHighlight:YES];
    }
}

- (BOOL)collectionView:(UICollectionView *)collectionView shouldSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    UICollectionViewCell *cell = [collectionView cellForItemAtIndexPath:indexPath];
    if (!self.canAddPhoto
        || cell.isSelected) {
        return NO;
    }
    if ([cell isKindOfClass:[YMSPhotoCell class]]) {
        YMSPhotoCell *photoCell = (YMSPhotoCell *)cell;
        [photoCell setNeedsAnimateSelection];
        if ([self shouldOrderSelection]) {
            photoCell.selectionOrder = self.selectedPhotos.count+1;
        }
    }
    return YES;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.row == 0) {
        [self.photoCollectionView deselectItemAtIndexPath:indexPath animated:NO];
        [self yms_presentCameraCaptureViewWithDelegate:self];
    }
    else if (NO == self.allowsMultipleSelection) {
        if (NO == self.shouldReturnImageForSingleSelection) {
            PHFetchResult *fetchResult = self.currentCollectionItem[@"assets"];
            PHAsset *asset = fetchResult[indexPath.item-1];
            [self.selectedPhotos addObject:asset];
            [self finishPickingPhotos:nil];
        } else {
            PHFetchResult *fetchResult = self.currentCollectionItem[@"assets"];
            PHAsset *asset = fetchResult[indexPath.item-1];
            
            if ([self.delegate respondsToSelector:@selector(photoPickerViewController:didFinishPickingMedia:)]) {
                [self.delegate photoPickerViewController:self didFinishPickingMedia:asset];
            }
            else {
                [self dismiss:nil];
            }
        }
    }
    else {
        PHFetchResult *fetchResult = self.currentCollectionItem[@"assets"];
        PHAsset *asset = fetchResult[indexPath.item-1];
        [self.selectedPhotos addObject:asset];
        self.doneItem.enabled = YES;
    }
}

- (void)collectionView:(UICollectionView *)collectionView didUnhighlightItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView cellForItemAtIndexPath:indexPath];
    if ([cell isKindOfClass:[YMSPhotoCell class]]) {
        [(YMSPhotoCell *)cell animateHighlight:NO];
    }
}

- (BOOL)collectionView:(UICollectionView *)collectionView shouldDeselectItemAtIndexPath:(NSIndexPath *)indexPath
{
    UICollectionViewCell *cell = [collectionView cellForItemAtIndexPath:indexPath];
    if ([cell isKindOfClass:[YMSPhotoCell class]]) {
        [(YMSPhotoCell *)cell setNeedsAnimateSelection];
    }
    return YES;
}

- (void)collectionView:(UICollectionView *)collectionView didDeselectItemAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.item == 0) {
        // The camera cell has no selected/deselected state, so we should present the camera on every touch on the cell
        [self yms_presentCameraCaptureViewWithDelegate:self];
        return;
    }
    PHFetchResult *fetchResult = self.currentCollectionItem[@"assets"];
    PHAsset *asset = fetchResult[indexPath.item-1];

    if ([self shouldOrderSelection]) {
        NSUInteger removedIndex = [self.selectedPhotos indexOfObject:asset];
        // Reload order higher than removed cell
        for (NSInteger i=removedIndex+1; i<self.selectedPhotos.count; i++) {
            PHAsset *needReloadAsset = self.selectedPhotos[i];
            YMSPhotoCell *cell = (YMSPhotoCell *)[collectionView cellForItemAtIndexPath:[NSIndexPath indexPathForItem:[fetchResult indexOfObject:needReloadAsset]+1 inSection:indexPath.section]];
            cell.selectionOrder = cell.selectionOrder-1;
        }
    }

    [self.selectedPhotos removeObject:asset];
    if (self.selectedPhotos.count == 0) {
        self.doneItem.enabled = NO;
    }
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    if (CGSizeEqualToSize(CGSizeZero, self.cellPortraitSize)
        || CGSizeEqualToSize(CGSizeZero, self.cellLandscapeSize)) {
        [self setupCellSize];
    }

    if ([[UIApplication sharedApplication] statusBarOrientation] == UIInterfaceOrientationLandscapeLeft
        || [[UIApplication sharedApplication] statusBarOrientation] == UIInterfaceOrientationLandscapeRight) {
        return self.cellLandscapeSize;
    }
    return self.cellPortraitSize;
}

#pragma mark - IBActions

- (IBAction)dismiss:(id)sender
{
    if ([self.delegate respondsToSelector:@selector(photoPickerViewControllerDidCancel:)]) {
        [self.delegate photoPickerViewControllerDidCancel:self];
    }
    else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (IBAction)presentAlbumPickerView:(id)sender
{
    YMSAlbumPickerViewController *albumPickerViewController = [[YMSAlbumPickerViewController alloc] initWithCollectionItems:self.collectionItems selectedCollectionItem:self.currentCollectionItem dismissalHandler:^(NSDictionary *selectedCollectionItem) {
        if (![self.currentCollectionItem isEqual:selectedCollectionItem]) {
            [self updateViewWithCollectionItem:selectedCollectionItem];
        }
        else {
            // If collection view doesn't update, camera won't start to run
            if (![self.session isRunning]) {
                [self.session startRunning];
            }
        }
    }];
    albumPickerViewController.view.tintColor = self.theme.tintColor;

    [self presentViewController:albumPickerViewController animated:YES completion:nil];
}

- (IBAction)finishPickingPhotos:(id)sender
{
    if ([self.delegate respondsToSelector:@selector(photoPickerViewController:didFinishPickingMedias:)]) {
        NSArray *finalMedias = nil;
        if (self.configuration.sortingType == YMSPhotoPickerSortingTypeSelection) {
            finalMedias = [self.selectedPhotos copy];
        } else {
            BOOL ascending = self.configuration.sortingType == YMSPhotoPickerSortingTypeCreationAscending;
            NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:ascending];
            finalMedias = [self.selectedPhotos sortedArrayUsingDescriptors:@[sortDescriptor]];
        }
        [self.delegate photoPickerViewController:self didFinishPickingMedias:finalMedias];
    }
    else {
        [self dismiss:nil];
    }
}

- (IBAction)presentSinglePhoto:(id)sender
{
    if (![sender isKindOfClass:[UILongPressGestureRecognizer class]]) {
        return;
    }
    
    UILongPressGestureRecognizer *gesture = sender;
    if (gesture.state == UIGestureRecognizerStateBegan) {
        if (_previewViewController) {
            return;
        }
        YMSPhotoCell *cell = (YMSPhotoCell*)gesture.view;
        NSIndexPath *indexPath = [self.photoCollectionView indexPathForCell:cell];
        
        PHFetchResult *fetchResult = self.currentCollectionItem[@"assets"];
        PHAsset *asset = fetchResult[indexPath.item-1];
        
        _previewViewController = [[YMSSingleMediaViewController alloc] initWithAsset:asset imageManager:self.imageManager];
        _previewViewController.view.frame = self.view.frame;
        _previewViewController.view.tintColor = self.theme.tintColor;
        
        if (!_previewTransition) {
            _previewTransition = [YMSSingleMediaTransition new];
        }
        _previewTransition.sourceImage = cell.thumbnailImage;
        _previewTransition.detailFrame = _previewViewController.mediaPreviewFrame;
        CGRect convertedFrame = [self.photoCollectionView convertRect:cell.frame toView:self.photoCollectionView.superview];
        _previewTransition.thumbnailFrame = convertedFrame;
        
        _previewViewController.transitioningDelegate = _previewTransition;
        _previewViewController.modalPresentationStyle = UIModalPresentationCustom;
        [self presentViewController:_previewViewController animated:YES completion:nil];
    }
    else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        if (!_previewViewController) {
            return;
        }
        UIView *cell = gesture.view;
        CGRect convertedFrame = [self.photoCollectionView convertRect:cell.frame toView:self.photoCollectionView.superview];
        _previewTransition.thumbnailFrame = convertedFrame;
        [_previewViewController dismissViewControllerAnimated:YES completion:nil];
        _previewViewController = nil;
    }
}

#pragma mark - UIImagePickerControllerDelegate

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info
{
    [picker dismissViewControllerAnimated:YES completion:^{

        // Enable camera preview when user allow it first time
        if (![self.session isRunning]) {
            [self.photoCollectionView reloadItemsAtIndexPaths:@[[NSIndexPath indexPathForItem:0 inSection:0]]];
        }
        
        // Save the image to Photo Album
        __block PHObjectPlaceholder *assetPlaceholder = nil;
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            
            // Create a PHAssetChangeRequest with the newly taken media
            PHAssetChangeRequest *assetRequest = nil;
            NSString *mediaType = [info objectForKey:UIImagePickerControllerMediaType];
            if (UTTypeConformsTo((__bridge CFStringRef)mediaType, kUTTypeImage)) {
                UIImage *image = [info objectForKey:UIImagePickerControllerOriginalImage];
                assetRequest = [PHAssetChangeRequest creationRequestForAssetFromImage:image];
            }
            else if (UTTypeConformsTo((__bridge CFStringRef)mediaType, kUTTypeMovie)) {
                NSURL *videoURL = [info objectForKey:UIImagePickerControllerMediaURL];
                assetRequest = [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:videoURL];
            }
            
            if (!assetRequest) {
                return;
            }
            
            // Create an asset placeholder. It will be used:
            // - to add the new asset into the current Photo Album (only needed for the non-smart albums)
            // - the fetch the resulting PHAsset at the end of the changes, to pass it to the delegate if needed
            assetPlaceholder = [assetRequest placeholderForCreatedAsset];
            
            PHAssetCollection *collection = self.currentCollectionItem[@"collection"];
            if (collection.assetCollectionType != PHAssetCollectionTypeSmartAlbum) {
                PHAssetCollectionChangeRequest *albumChangeRequest = [PHAssetCollectionChangeRequest changeRequestForAssetCollection:collection assets:self.currentCollectionItem[@"assets"]];
                [albumChangeRequest addAssets:@[assetPlaceholder]];
            }
            
        } completionHandler:^(BOOL success, NSError *error) {
            if (success) {
                self.needToSelectFirstPhoto = YES;
            }

            if (!self.allowsMultipleSelection) {
                if ([self.delegate respondsToSelector:@selector(photoPickerViewController:didFinishPickingMedia:)]) {
                    // Fetch the newly created PHAsset
                    PHFetchResult *assets = [PHAsset fetchAssetsWithLocalIdentifiers:@[assetPlaceholder.localIdentifier] options:nil];
                    PHAsset *createdAsset = assets.firstObject;
                    if (createdAsset) {
                        [self.delegate photoPickerViewController:self didFinishPickingMedia:createdAsset];
                    }
                }
                else {
                    [self dismiss:nil];
                }
            }
        }];
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    [picker dismissViewControllerAnimated:YES completion:^(){
        // Enable camera preview when user allow it first time
        if (![self.session isRunning]) {
            [self.photoCollectionView reloadItemsAtIndexPaths:@[[NSIndexPath indexPathForItem:0 inSection:0]]];
        }
    }];
}

#pragma mark - Privates

- (void)updateViewWithCollectionItem:(NSDictionary *)collectionItem
{
    self.currentCollectionItem = collectionItem;
    PHCollection *photoCollection = self.currentCollectionItem[@"collection"];
    
    UIButton *albumButton = [UIButton buttonWithType:UIButtonTypeSystem];
    albumButton.tintColor = self.theme.titleLabelTextColor;
    albumButton.titleLabel.font = self.theme.titleLabelFont;
    [albumButton addTarget:self action:@selector(presentAlbumPickerView:) forControlEvents:UIControlEventTouchUpInside];
    [albumButton setTitle:photoCollection.localizedTitle forState:UIControlStateNormal];
    UIImage *arrowDownImage = [UIImage imageNamed:@"YMSIconSpinnerDropdwon" inBundle:[NSBundle bundleForClass:self.class] compatibleWithTraitCollection:nil];
    arrowDownImage = [arrowDownImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [albumButton setImage:arrowDownImage forState:UIControlStateNormal];
    [albumButton sizeToFit];
    albumButton.imageEdgeInsets = UIEdgeInsetsMake(0.0, albumButton.frame.size.width - (arrowDownImage.size.width) + 10, 0.0, 0.0);
    albumButton.titleEdgeInsets = UIEdgeInsetsMake(0.0, -arrowDownImage.size.width, 0.0, arrowDownImage.size.width + 10);
    // width + 10 for the space between text and image
    albumButton.frame = CGRectMake(0.0, 0.0, CGRectGetWidth(albumButton.bounds) + 10, CGRectGetHeight(albumButton.bounds));

    [self.navigationBar.items firstObject].titleView = albumButton;

    [self.photoCollectionView reloadData];
    [self refreshPhotoSelection];
}

- (UIImage *)yms_orientationNormalizedImage:(UIImage *)image
{
    if (image.imageOrientation == UIImageOrientationUp) return image;

    UIGraphicsBeginImageContextWithOptions(image.size, NO, image.scale);
    [image drawInRect:CGRectMake(0.0, 0.0, image.size.width, image.size.height)];
    UIImage *normalizedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return normalizedImage;
}

- (BOOL)allowsMultipleSelection
{
    return (self.numberOfMediaToSelect != 1);
}

- (void)refreshPhotoSelection
{
    PHFetchResult *fetchResult = self.currentCollectionItem[@"assets"];
    NSUInteger selectionNumber = self.selectedPhotos.count;

    for (int i=0; i<fetchResult.count; i++) {
        PHAsset *asset = [fetchResult objectAtIndex:i];
        if ([self.selectedPhotos containsObject:asset]) {

            // Display selection
            [self.photoCollectionView selectItemAtIndexPath:[NSIndexPath indexPathForItem:i+1 inSection:0] animated:NO scrollPosition:UICollectionViewScrollPositionNone];
            if ([self shouldOrderSelection]) {
                YMSPhotoCell *cell = (YMSPhotoCell *)[self.photoCollectionView cellForItemAtIndexPath:[NSIndexPath indexPathForItem:i+1 inSection:0]];
                cell.selectionOrder = [self.selectedPhotos indexOfObject:asset]+1;
            }

            selectionNumber--;
            if (selectionNumber == 0) {
                break;
            }
        }
    }
}

- (BOOL)canAddPhoto
{
    return (self.selectedPhotos.count < self.numberOfMediaToSelect
            || self.numberOfMediaToSelect == 0);
}

- (void)fetchCollections
{
    PHFetchOptions *fetchOptions = [[PHFetchOptions alloc] init];
    fetchOptions.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
    
    NSMutableArray *predicates = [NSMutableArray new];
    if(self.configuration.sourceType == YMSPhotoPickerSourceTypePhoto || self.configuration.sourceType == YMSPhotoPickerSourceTypeBoth) {
        NSPredicate *photoPredicate = [NSPredicate predicateWithFormat:@"mediaType = %d", PHAssetMediaTypeImage];
        [predicates addObject:photoPredicate];
    }
    if(self.configuration.sourceType == YMSPhotoPickerSourceTypeVideo || self.configuration.sourceType == YMSPhotoPickerSourceTypeBoth) {
        NSPredicate *videoPredicate = [NSPredicate predicateWithFormat:@"mediaType = %d", PHAssetMediaTypeVideo];
        [predicates addObject:videoPredicate];
    }
    NSPredicate *predicate = [NSCompoundPredicate orPredicateWithSubpredicates:predicates];
    fetchOptions.predicate = predicate;

    NSMutableArray *allAblums = [NSMutableArray array];

    __block __weak void (^weakFetchAlbums)(PHFetchResult *collections);
    void (^fetchAlbums)(PHFetchResult *collections);
    weakFetchAlbums = fetchAlbums = ^void(PHFetchResult *collections) {
        for (PHCollection *collection in collections) {
            if ([collection isKindOfClass:[PHAssetCollection class]]) {
                PHAssetCollection *assetCollection = (PHAssetCollection *)collection;
                PHFetchResult *assetsFetchResult = [PHAsset fetchAssetsInAssetCollection:assetCollection options:fetchOptions];
                if (assetsFetchResult.count > 0) {
                    [allAblums addObject:@{@"collection": assetCollection
                                           , @"assets": assetsFetchResult}];
                }
            }
            else if ([collection isKindOfClass:[PHCollectionList class]]) {
                // If there are more sub-folders, dig into the collection to fetch the albums
                PHCollectionList *collectionList = (PHCollectionList *)collection;
                PHFetchResult *fetchResult = [PHCollectionList fetchCollectionsInCollectionList:(PHCollectionList *)collectionList options:nil];
                weakFetchAlbums(fetchResult);
            }
        }
    };

    // Manually choose all the smart albums to show
    PHFetchResult *userLibrary = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeSmartAlbumUserLibrary options:nil];
    PHFetchResult *favorites = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeSmartAlbumFavorites options:nil];
    PHFetchResult *videos = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeSmartAlbumVideos options:nil];
    PHFetchResult *screenshots = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeSmartAlbumScreenshots options:nil];
    PHFetchResult *selfPortraits = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeSmartAlbumSelfPortraits options:nil];
    PHFetchResult *albums = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAny options:nil];
    NSArray *collections = @[userLibrary, favorites, videos, screenshots, selfPortraits, albums];
    
    for (PHFetchResult *collection in collections) {
        fetchAlbums(collection);
    }
    self.collectionItems = [allAblums copy];
}

- (void)setupCellSize
{
    UICollectionViewFlowLayout *layout = (UICollectionViewFlowLayout *)self.photoCollectionView.collectionViewLayout;

    // Fetch shorter length
    CGFloat arrangementLength = MIN(CGRectGetWidth(self.view.frame), CGRectGetHeight(self.view.frame));

    CGFloat minimumInteritemSpacing = layout.minimumInteritemSpacing;
    UIEdgeInsets sectionInset = layout.sectionInset;

    NSUInteger numberOfColumns = self.configuration.numberOfColumns;
    CGFloat totalInteritemSpacing = MAX((numberOfColumns - 1), 0) * minimumInteritemSpacing;
    CGFloat totalHorizontalSpacing = totalInteritemSpacing + sectionInset.left + sectionInset.right;

    // Caculate size for portrait mode
    CGFloat size = (CGFloat)floor((arrangementLength - totalHorizontalSpacing) / numberOfColumns);
    self.cellPortraitSize = CGSizeMake(size, size);

    // Caculate size for landsacpe mode
    CGFloat safeAreaInsets = 0;
    if (@available(iOS 11.0, *)) {
        safeAreaInsets = self.view.safeAreaInsets.left + self.view.safeAreaInsets.right;
    }
    arrangementLength = MAX(CGRectGetWidth(self.view.frame), CGRectGetHeight(self.view.frame)) - safeAreaInsets;
    NSUInteger numberOfPhotoColumnsInLandscape = (arrangementLength - sectionInset.left + sectionInset.right)/size;
    totalInteritemSpacing = MAX((numberOfPhotoColumnsInLandscape - 1), 0) * minimumInteritemSpacing;
    totalHorizontalSpacing = totalInteritemSpacing + sectionInset.left + sectionInset.right;
    size = (CGFloat)floor((arrangementLength - totalHorizontalSpacing) / numberOfPhotoColumnsInLandscape);
    self.cellLandscapeSize = CGSizeMake(size, size);
}

- (BOOL)shouldOrderSelection
{
    return self.configuration.sortingType == YMSPhotoPickerSortingTypeSelection;
}

- (void)adjustStatusBarSpace
{
    if (![self.view respondsToSelector:@selector(safeAreaInsets)]) {
        CGFloat space = UIDeviceOrientationIsLandscape(UIDevice.currentDevice.orientation) ? 0 : 20;
        self.navigationBarTopConstraint.constant = space;
    }
}

#pragma mark - PHPhotoLibraryChangeObserver

- (void)photoLibraryDidChange:(PHChange *)changeInstance {
    // Check if there are changes to the assets we are showing.
    PHFetchResult *fetchResult = self.currentCollectionItem[@"assets"];
    
    PHFetchResultChangeDetails *collectionChanges = [changeInstance changeDetailsForFetchResult:fetchResult];
    if (collectionChanges == nil) {

        [self fetchCollections];

        if (self.needToSelectFirstPhoto) {
            self.needToSelectFirstPhoto = NO;

            fetchResult = [self.collectionItems firstObject][@"assets"];
            PHAsset *asset = [fetchResult firstObject];
            [self.selectedPhotos addObject:asset];
            self.doneItem.enabled = YES;
        }

        return;
    }
    
    /*
     Change notifications may be made on a background queue. Re-dispatch to the
     main queue before acting on the change as we'll be updating the UI.
     */
    dispatch_async(dispatch_get_main_queue(), ^{
        // Get the new fetch result.
        PHFetchResult *fetchResult = [collectionChanges fetchResultAfterChanges];
        NSInteger index = [self.collectionItems indexOfObject:self.currentCollectionItem];
        self.currentCollectionItem = @{
                                       @"assets": fetchResult,
                                       @"collection": self.currentCollectionItem[@"collection"]
                                       };
        if (index != NSNotFound) {
            NSMutableArray *updatedCollectionItems = [self.collectionItems mutableCopy];
            [updatedCollectionItems replaceObjectAtIndex:index withObject:self.currentCollectionItem];
            self.collectionItems = [updatedCollectionItems copy];
        }
        UICollectionView *collectionView = self.photoCollectionView;
        
        if (![collectionChanges hasIncrementalChanges] || [collectionChanges hasMoves]
            || ([collectionChanges removedIndexes].count > 0
                && [collectionChanges changedIndexes].count > 0)) {
            // Reload the collection view if the incremental diffs are not available
            [collectionView reloadData];
        }
        else {
            /*
             Tell the collection view to animate insertions and deletions if we
             have incremental diffs.
             */
            [collectionView performBatchUpdates:^{
                
                NSIndexSet *removedIndexes = [collectionChanges removedIndexes];
                NSMutableArray *removeIndexPaths = [NSMutableArray arrayWithCapacity:removedIndexes.count];
                [removedIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
                    [removeIndexPaths addObject:[NSIndexPath indexPathForItem:idx+1 inSection:0]];
                }];
                if ([removedIndexes count] > 0) {
                    [collectionView deleteItemsAtIndexPaths:removeIndexPaths];
                }
                
                NSIndexSet *insertedIndexes = [collectionChanges insertedIndexes];
                NSMutableArray *insertIndexPaths = [NSMutableArray arrayWithCapacity:insertedIndexes.count];
                [insertedIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
                    [insertIndexPaths addObject:[NSIndexPath indexPathForItem:idx+1 inSection:0]];
                }];
                if ([insertedIndexes count] > 0) {
                    [collectionView insertItemsAtIndexPaths:insertIndexPaths];
                }
                
                NSIndexSet *changedIndexes = [collectionChanges changedIndexes];
                NSMutableArray *changedIndexPaths = [NSMutableArray arrayWithCapacity:changedIndexes.count];
                [changedIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
                    NSIndexPath *indexPath = [NSIndexPath indexPathForItem:idx inSection:0];
                    if (![removeIndexPaths containsObject:indexPath]) {
                        // In case reload selected cell, they were didSelected and re-select. Ignore them to prevent weird transition.
                        if (self.needToSelectFirstPhoto) {
                            if (![collectionView.indexPathsForSelectedItems containsObject:indexPath]) {
                                [changedIndexPaths addObject:indexPath];
                            }
                        }
                        else {
                            [changedIndexPaths addObject:indexPath];
                        }
                    }
                }];
                if ([changedIndexes count] > 0) {
                    [collectionView reloadItemsAtIndexPaths:changedIndexPaths];
                }
            } completion:^(BOOL finished) {
                if (self.needToSelectFirstPhoto) {
                    self.needToSelectFirstPhoto = NO;

                    PHAsset *asset = [fetchResult firstObject];
                    [self.selectedPhotos addObject:asset];
                    self.doneItem.enabled = YES;
                }
                [self refreshPhotoSelection];
            }];
        }
    });
}

@end
