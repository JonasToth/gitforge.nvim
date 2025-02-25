# CHANGELOG

## [unreleased]

- consistent telescope picker for different issue sources
    - list of issues retrieved from repository
    - opened issue buffers
    - pinned issues
- telescope picker to select the issue labels using multi-selection
    - stores the project labels in a cache
    - if the cache file exists, this file is used as basis and the cache is asynchronously
      updated; _changes are not propagated to the picker_

## 0.1.0 - 2025-01-21

This is the first tagged release. Have fun :)

- fetch issue list and view it in telescope picker
- viewing an issue and its comment
- editing issue elements (title, description, labels, assignee, state)
- go to browser view of the issue, update the issue
- pin issue to write it to local storage and have it always available
- telescope picker for open issue buffers (Opened Issues)
- telescope picker for pinned Issues
- enablement of GitLab and Github
- per project configuration of issue-provider and choosen project
