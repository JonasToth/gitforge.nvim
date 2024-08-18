# Spec: Project

A project is the resource managed by the git force, e.g. a repository and the logical unit of
configuration. The project should be a `git` repository hosted on the git forge. Communication with
project items should happen through a git forge specific CLI tool, e.g. `gh-cli`.
Additionally, the project serves as an disambiguator of issue numbers and the like.

## Requirements

### Necessities

- a project is identified by an owner and the project-name
    - that usually matches the project identification of the URL in the git forge
    - e.g. `llvm/llvm-project`
- a project should have a corresponding directory path on the local machine `nvim` runs on
    - there might be a default project that would be queried if no other project is found
- the correspondence from project <-> directory path is established through path matching, the
  longest matching prefix forms the correspondence (most specific match wins)
- actions are always executed in the context of a project
    - determination of the active project happens by inspecting the current execution directory
      (`:cd` in `nvim` shows the current directory)
- each project can receive specific configuration options that override the default options,
  missing options are filled with default choices

### Nice to Have

- integration of the current project into a status line or so, like `git` branches
- it would be nice to have a project wide definition of "interesting to me" that triggers
  automatic pinning and updating of issues, PRs and the like
    - like automatically pin all issues assigned to me
- autocompletion is filled with project specific info
    - list of all labels is cached (and updated) and provided in auto complete when writing labels
    - list of contributors to tag persons of interest

## Non-Functional Requirements

- the project identifier (or a derived string from that) serves as directory for content caching
- project wide configurations should be agnostic to the git forge backend in use
    - if a project does not use `labels` to differentiate issue types, the backend should translate
      the label concepts to the issue type concept

## Customizations

- what git forge to use as backend
- backend specific settings that may be necessary (endpoints or the like)
- configuration of general views like [Issue List](issue_list.md)
- configuration of what to show in an issue (?)
