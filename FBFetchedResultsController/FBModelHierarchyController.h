/*
 *  Copyright (c) 2015, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant 
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import <CoreData/CoreData.h>
#import <Foundation/Foundation.h>

/**
 @summary The types of changes to the objects that are returned by the consumer.
 */
typedef NS_ENUM(NSUInteger, FBModelChangeType) {
  FBModelChangeTypeDelete = NSFetchedResultsChangeDelete,
  FBModelChangeTypeInsert = NSFetchedResultsChangeInsert,
  FBModelChangeTypeMove = NSFetchedResultsChangeMove,
  FBModelChangeTypeUpdate = NSFetchedResultsChangeUpdate,
};

@protocol FBModelHierarchyControllerDelegate;

@protocol FBModelHierarchySectionInfo <NSFetchedResultsSectionInfo>
@end

@interface FBModelHierarchyController : NSObject

/**
 @summary Initializes the receiver to compare the objects based on object equality.

 @param filterPredicate The filter to be applied to all objects.
 @param sortDescriptors Sorting to be applied to the arrangedObjects.
 @param sectionNameKeyPath The keyPath on the objects used by the receiver to arrange its contents into sections.
 */
- (instancetype)initWithFilterPredicate:(NSPredicate *)filterPredicate
                        sortDescriptors:(NSArray *)sortDescriptors
                     sectionNameKeyPath:(NSString *)sectionNameKeyPath;

#pragma mark - Configuration Properties

/**
 @summary The object that is notified when the hierarchy changes.
 */
@property (nonatomic, assign) id<FBModelHierarchyControllerDelegate> delegate;

/**
 @summary The receiver's predicate, which is used to filter the models in the hierarchy.

 @desc The objects that are vended from the receiver will exclude those that do not match the predicate.
 */
@property (nonatomic, copy, readonly) NSPredicate *filterPredicate;

/**
 @summary The keyPath on the objects used by the receiver to arrange its contents into sections.
 */
@property (nonatomic, copy, readonly) NSString *sectionNameKeyPath;

/**
 @summary The sort descriptors for the objects in the hierarchy

 @desc An array of NSSortDescriptor objects used by the receiver to arrange its contents.
 */
@property (nonatomic, copy, readonly) NSArray *sortDescriptors;

#pragma mark - Model Accessors

/**
 @summary The sorted and filtered models.

 @desc This property is observable using key-value observing.
 */
@property (nonatomic, retain, readonly) NSArray *arrangedObjects;

/**
 Returns the number of objects currently in the receiver (after filtering).
 */
@property (nonatomic, assign, readonly) NSUInteger countOfArrangedObjects;

/**
 @summary Finds an object from the hierarchy.

 @desc If objects are not equal (isEqual:) they will not be found through this API.  This may be the case if objects are
 replaced using the objectIDKeyPath.  In that case, you will get nil for previous versions of an object in the receiver.

 @param object The object to find in the hierarchy.

 @returns The lowest index of the object.  NSNotFound if the object is not in the hierarchy.
 */
- (NSIndexPath *)indexPathOfArrangedObject:(id)object;

/**
 @summary Retrives an object from the hierarchy.

 @desc Calling this method with an index beyond the count will raise an NSRangeException.

 @param indexPath The indexPath to find the object at.

 @returns The object in the hierarchy at the specified indexPath.
 */
- (id)objectInArrangedObjectsAtIndexPath:(NSIndexPath *)indexPath;

/**
 An ordered set of section objects, which conform to FBModelHierarchySectionInfo.
 */
- (NSOrderedSet *)sections;

@end

/**
 @summary A delegate for an object that acts as a model hierarchy.

 @desc An instance of a model will notify its delegate when its contents have been changed due to an add, remove, move
 or update.  This delegate is a parallel to that of NSFetchedResultsController, with a general sender.
 */
@protocol FBModelHierarchyControllerDelegate

/**
 @summary Notifies the receiver that a model object has been added, removed, moved or updated.

 @desc This delegate method is designed around the expectations of UITableView's mutation methods.  Notably, if the
 callbacks are within a batch update, the deletes and updates are based on the indices before any changes are applied.
 Moves have an indexPath based on the indices before any changes are applied and a newIndexPath based on the indices
 after all of the changes are applied.  If the consumer of these callbacks is not a UITableView, it must follow similar
 logic to UITableView and collect all indices to delete, delete them, then do all inserts.  Moves should be treated as
 an insert and delete, just as is implied by NSFetchedResultsControllerDelegate's callback mapping to UITableView.

 If you want to use moveRowAtIndexPath:toIndexPath:, you are responsible for also updating the contents of the cell.
 The indexPath should resolve to the index prior to any changes, like a delete, and the toIndexPath should resolve to
 the indexPath after all changes are applied, like an insert.  You cannot call reloadRowsAtIndexPaths:withRowAnimation:
 for a cell that you also move.

 When this delegate method is called, the arrangedObjects do not yet reflect the changes, so they will match the methods
 on UITableView (ex: cellForRowAtIndexPath:).

 @param modelHierarchyController The model hierarchy controller that sent the message.
 @param object The model object that changed.
 @param indexPath The indexPath of the object in the model hierarchy's collection (always based on the hierarchy before the batch is applied).
 @param changeType The type of change.  @see FBModelChangeType
 @param newIndexPath The destination indexPath for the object for add or move changes (otherwise NSNotFound; always based on the hierarchy after the batch is applied).
 */
- (void)modelHierarchyController:(FBModelHierarchyController *)modelHierarchyController
                 didChangeObject:(id)object
                     atIndexPath:(NSIndexPath *)indexPath
                   forChangeType:(FBModelChangeType)changeType
                    newIndexPath:(NSIndexPath *)newIndexPath;

- (void)modelHierarchyController:(FBModelHierarchyController *)modelHierarchyController
                didChangeSection:(id<FBModelHierarchySectionInfo>)section
                         atIndex:(NSUInteger)index
                   forChangeType:(FBModelChangeType)changeType;

/**
 @summary Returns the corresponding section index entry for a given section name.

 @desc The typical implementation returns the capitalized first letter of the section name.
 */
- (NSString *)modelHierarchyController:(FBModelHierarchyController *)modelHierarchyController
       sectionIndexTitleForSectionName:(NSString *)sectionName;

/**
 @summary Notifies the receiver that the model hierarchy controller has completed processing of one or more changes due to an
 add, remove, move or update.

 @param modelHierarchyController The model hierarchy controller that sent the message.
 */
- (void)modelHierarchyControllerDidChangeContent:(FBModelHierarchyController *)modelHierarchyController;

/**
 @summary Notifies the receiver that the model hierarchy controller is about to start processing of one or more changes due
 to an add, remove, move or update.

 @param modelHierarchyController The model hierarchy controller that sent the message.
 */
- (void)modelHierarchyControllerWillChangeContent:(FBModelHierarchyController *)modelHierarchyController;

@end
