# Spec: Viewing a Single Issue

The **Issue View** provides the content of a single issue. It serves as the interaction point with
single issues, provides access to its comments and provides means to modify the issues.

The underlying loading of the contents may happen through the [Issue Cache](spec_issue_cache.md)

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
- all viewers of the issue should at least provide basic markdown hightlighting
    - telescope previewers
    - opening the buffer
- issue interaction is available through key binding
    - closing the view (q)
    - adding a comment
    - assigning the issue / unassigning the issue
    - adding / removing label(s)
    - adding / removing projects / milestones
    - update the description
    - changing the state (open -> close; close -> open; state transition ala jira)
    - pin the issue which should persist its content locally

### Nice to Have

- sorting comments by date ascending / descending
- different strategies on how to open the issue view
    - open a float
    - open a split
    - replace current buffer
    - "always open in left column" like a filesystem-tree viewer does
- auto-updating the issue content with a timer to make new comments available without user interaction

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
