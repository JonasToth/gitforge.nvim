# Spec: Defining the Issue List

The **Issue List** is the central starting point to the work with issues. It provides access
to the issue tracker and serves as selector for individual issues.

## Requirements

### Necessities

- provide an issue-picker for `telescope`
    - list of issues are the entries
    - previews provides [content of the issue](spec_issue_view.md)
- provide a way to query a project with different conditions for issues
    - all issues assigned to {me, noone, username}
    - all issues created by {me, someone}
    - all issues with specific labels (e.g. bugs)
    - limiting the number of issues
    - combination of different criteria must be possible
- provide an issue preview with meta data and description, should be instantly available
- the issue list should contain (at least configurable) the following items
    - issue number
    - issue title (may be shortened)
    - assignee
    - labels
- the search ordinal should respect
    - creator
    - assignee
    - issue-number
    - labels
    - title
- the issue list is populated as follows. Offline work must still be possible
    - network-queried issues from the git forge
    - issues in buffers
    - issues from the persistent issue cache

### Nice to Have

- changing the filter criteria interactively when the picker is showing
    - like adding or removing labels
    - adding or remove assignees
- listing issues for a specific project / milestone
- provide custom sorting
    - by date
    - by label
    - by assignee
    - by creator
- devicons for specific labels
    - e.g. replace `bug` label with bug-icon
- customization of output
- issue-triage like features
    - e.g. multi-selection of issues in the list and then assigning a specific label or the like

## Non-Functional Requirements

- issue content that is loaded, e.g. in the previewer should be cached for snappy "detail" loading
- interaction should feel like working with multiple open files / buffers
    - "my issues must always be available" -> quick access, best case even without internet
    - focus on day to day developers work and not project management things

## Customizations

- which columns shall be present
- width of each column
- order of the columns
- icon replacements (bug label -> bug icon)
