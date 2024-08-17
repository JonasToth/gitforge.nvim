# Spec: Project

A project is the resource managed by the git force, e.g. a repository and the logical unit of
configuration. The project should be a `git` repository hosted on the git forge. Communication with
project items should happen through a git forge specific CLI tool, e.g. `gh-cli`.
Additionally, the project serves as an disambiguator of issue numbers and the like.
