# Spec: Viewing a Single Issue

The **Issue View** provides the content of a single issue. It serves as the interaction point with
single issues, provides access to its comments and provides means to modify the issues.

The underlying loading of the contents may happen through the [Issue Cache](issue_cache.md)

## Requirements

### Necessities

- the content of the issue must contain title, metadata, comments
- metadata is
    - issue number
    - assginee(s)
    - creator
    - created at
    - state (open, close, maybe more states like jira has)
    - labels
- the issue is "rendered" in a markdown buffer
    - markdown specific plugins handle aesthetics
- all viewers of the issue should at least provide basic markdown hightlighting
    - telescope previewers
    - opening the buffer
- openening an issue opens a new window or tab, structurally different than the previous buffer
    - the issue view should no hinder normal development and closing the view should lead back
      directly to the previously open file/buffer
- issue interaction is available through key binding (using `localleader`)
    - updating the view to retrieve the latest state
    - closing the view
    - adding a comment
    - changing the title
    - changing assignee / unassigning the issue
    - changing label(s)
    - changing the description
    - changing the state (open -> close; close -> open; state transition ala jira)

### Nice to Have

- pin the issue which should persist its content locally
- sorting comments by date ascending / descending
- configure different strategies on how to open the issue view
    - open a float
    - open a split
    - replace current buffer
    - "always open in left column" like a filesystem-tree viewer does
    - integrate with [no-neck-pain.nvim](https://github.com/shortcuts/no-neck-pain.nvim)
- auto-updating the issue content with a timer to make new comments available without user interaction
- adding / removing projects / milestones

## Non-Functional Requirements

- the content of issues shall be cached in buffers
- priority lies on reading issue content, comments and adding comments
    - the daily development work requires reading again "what the problem was"
    - providing feedback, discuss how to approach the issue and asking for clarifications are most
      frequent interactions
- be fast with issues to get back to work
- allow "sidebar-style" presentation to have the issue next to code

## Customizations

- icons or so for labels and state
- folding for comments
    - works with treesitter based folding
    - should be configurable on what to fold away by default
- folding of `<detail>` sections (in comments)
- folding of `hidden` comments
- [foldtext.nvim](https://github.com/OXY2DEV/foldtext.nvim) seems a to be a fitting plugin for that
