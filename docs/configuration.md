# Configuration

This page shows the available configuration options and their corresponding default values.
The out-of-the-box experience will use Github.

## General Settings

General settings that change the default experience:

    M.opts.timeout = 3500
    M.opts.default_issue_provider = "gitforge.gh.issue"

## Issue Settings

Keys to interact on an issue buffer:

    opts.issue_keys.close = "q"
    opts.issue_keys.update = "<localleader>u"
    opts.issue_keys.comment = "<localleader>c"
    opts.issue_keys.title = "<localleader>t"
    opts.issue_keys.labels = "<localleader>l"
    opts.issue_keys.assignees = "<localleader>a"
    opts.issue_keys.description = "<localleader>d"
    opts.issue_keys.state = "<localleader>s"

## Github Settings

Github specific settings:

    opts.github.executable = "gh"

