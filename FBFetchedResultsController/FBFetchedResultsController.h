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

@protocol FBFetchedResultsControllerDelegate;

/**
 A drop-in replacement for NSFetchedResultsController built to work around the fact that NSFetchedResultsController does
 not work with parent/child contexts. See NSFetchedResultsController for documentation.
 
 IMPORTANT: Any time you call [NSManagedObjectContext -mergeChangesFromContextDidSaveNotification:], you must call
 [FBFetchedResultsController +didMergeChangesFromContextDidSaveNotification:intoContext:].
 */
@interface FBFetchedResultsController : NSObject

+ (void)didMergeChangesFromContextDidSaveNotification:(NSNotification *)notification
                                          intoContext:(NSManagedObjectContext *)context;

+ (void)deleteCacheWithName:(NSString *)name;

- (instancetype)initWithFetchRequest:(NSFetchRequest *)fetchRequest
                managedObjectContext:(NSManagedObjectContext *)managedObjectContext
                  sectionNameKeyPath:(NSString *)sectionNameKeyPath
                           cacheName:(NSString *)cacheName;

@property (nonatomic, copy, readonly) NSString *cacheName; // not used
@property (nonatomic, assign) id <FBFetchedResultsControllerDelegate> delegate;
@property (nonatomic, copy, readonly) NSArray *fetchedObjects;
@property (nonatomic, retain, readonly) NSFetchRequest *fetchRequest;
@property (nonatomic, retain, readonly) NSManagedObjectContext *managedObjectContext;
@property (nonatomic, copy, readonly) NSArray *sectionIndexTitles;
@property (nonatomic, copy, readonly) NSString *sectionNameKeyPath;
@property (nonatomic, copy, readonly) NSArray *sections;

- (NSIndexPath *)indexPathForObject:(id)object;
- (id)objectAtIndexPath:(NSIndexPath *)indexPath;
- (BOOL)performFetch:(NSError **)error;
- (NSInteger)sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)sectionIndex;
- (NSString *)sectionIndexTitleForSectionName:(NSString *)sectionName;

@end

@protocol FBFetchedResultsControllerDelegate <NSObject>

@optional

- (void)controllerWillChangeContent:(FBFetchedResultsController *)controller;

- (void)controller:(FBFetchedResultsController *)controller
   didChangeObject:(id)anObject
       atIndexPath:(NSIndexPath *)indexPath
     forChangeType:(NSFetchedResultsChangeType)type
      newIndexPath:(NSIndexPath *)newIndexPath;

- (void)controller:(FBFetchedResultsController *)controller
  didChangeSection:(id<NSFetchedResultsSectionInfo>)sectionInfo
           atIndex:(NSUInteger)sectionIndex
     forChangeType:(NSFetchedResultsChangeType)type;

- (void)controllerDidChangeContent:(FBFetchedResultsController *)controller;

- (NSString *)controller:(FBFetchedResultsController *)controller sectionIndexTitleForSectionName:(NSString *)sectionName;

@end

