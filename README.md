FBFetchedResultsController
==========================

[![Build Status](https://travis-ci.org/facebook/FBFetchedResultsController.svg?branch=master)](https://travis-ci.org/facebook/FBFetchedResultsController)

A drop-in replacement for `NSFetchedResultsController` built to work around the fact that `NSFetchedResultsController` does not work well with parent/child contexts.

From Apple's [doc on NSManagedObject](https://developer.apple.com/library/ios/documentation/Cocoa/Reference/CoreDataFramework/Classes/NSManagedObjectContext_Class/):

> When you save changes in a context, the changes are only committed “one store up.” If you save a child context, changes are pushed to its parent. These changes are not saved to the persistent store until the root context is saved. (A root managed object context is one whose parent is nil.) In addition, a parent does not pull changes from children before it saves. You must save a child contexts if you want ultimately to commit the changes.

See [`NSFetchedResultsController`](https://developer.apple.com/library/ios/documentation/CoreData/Reference/NSFetchedResultsController_Class/) for documentation.

Usage
-----

- Use `FBFetchedResultsController` where you currently use `NSFetchedResultsController`
- **Important:** Call `[FBFetchedResultsController +didMergeChangesFromContextDidSaveNotification:intoContext:]` any time you call `[NSManagedObjectContext -mergeChangesFromContextDidSaveNotification:]`.

Authors
-------

`FBFetchedResultsController` was written at Facebook by [Nicolas Spiegelberg](https://www.facebook.com/nspiegelberg).
The underlying helper `FBModelHierarchyController` was written by Todd Krabach.

License
-------

`FBFetchedResultsController` is BSD-licensed. See `LICENSE`.
