---
title: Batch import tracks from folders and set region
layout: default
nav_order: 2
---

# Batch import tracks from folders and set region

| Info and Status         |                 |
| ----------------------- | --------------- |
| Spec'd                  | ✅               |
| Implemented             | ✅               |

This script does two things:
1. It batch imports tracks from folders
    Choose directory that contains only folders whose contents you want to import.
    Choose file extension(s) of files you want to import
    Choose how many seconds of gap there should be between the items of each folder, if any.
    This script will then go into each folder and place their items at the same time position on tracks downward from the current one, generating new ones if need be, sorting items numerically or alphabetically.
2. It makes and sets regions to respective items length and names them after each parent folder
    After importing the items of a folder, this script will create a region of the same length as the longest clip inside it and name it after the parent folder.


> [!info] Note that this script intentionally only goes one level deep
> Note that this script intentionally only goes one level deep, not recursively into the folder tree. You can select the parent folder that contains multiple folders, only those will be checked one level deep from the parent.