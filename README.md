FBFetchedResultsController
==========================

A drop-in replacement for `NSFetchedResultsController` built to work around the fact that `NSFetchedResultsController` does not work well with parent/child contexts. See `NSFetchedResultsController` for documentation.

Usage
-----

- Use `FBFetchedResultsController` where you currently use `NSFetchedResultsController`
- **Important:** Call `[FBFetchedResultsController +didMergeChangesFromContextDidSaveNotification:intoContext:]` any time you call `[NSManagedObjectContext -mergeChangesFromContextDidSaveNotification:]`.

Authors
-------

`FBFetchedResultsController` was written at Facebook by [Nicolas Spiegelberg](https://www.facebook.com/nspiegelberg).

License
-------

`FBFetchedResultsController` is BSD-licensed. See `LICENSE`.
