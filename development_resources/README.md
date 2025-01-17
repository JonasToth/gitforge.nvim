# Where is this Going?

### Ambitions

In short, this plugin tries to provide access to

- issues
- pull requests
- (maybe) CI/CD information

for a variety of git forges, namely GitHub, GitLab, Jira (issues at least)/Bitbucket and maybe
Gitea. The user interface should be the same for the different git forges. Practically, this
plugin wraps CLI tools for each forge, even though it could interact with the API directly.

The day-to-day interactions should be as fast as possible and not distract the user.
Enabling at least basic offline work should be possible.

The plugin should be well documented and the code easy to read. Tests are great to have, too!

### Realities

This is my first nvim plugin and I can only work on it in my free time. This project is a hobby
and does not have highest priority for me.
The code should be easy to read, but in reality I am figuring stuff out on the go.
Github is the starting point and likely the driver on how things are going to work.
If a different forge has concepts that clash with Github, the Github-way will likely win.
But if I really need something to work differently and can't figure out how to do it without
breaking something else, I will likely break things. This could happen to Github if I need GitLab
more than Github.

Chances are that I won't need to interact with Bitbucket anymore in the future and I have no
interaction with gitea. These forges will most likely not work without external contributions.

[jirac.nvim](https://github.com/janBorowy/jirac.nvim) exists and a specific Jira plugin will always win against this plugin.

## Near Goals 

The goal of this plugin is to keep most daily developer interactions with the project's git forge
within `nvim`. Especially quick actions like assigning an issue or writing a comment should not
require a context switch to the browser.
The plugin goes for functionality first, then customizability and finally asthetics
(maybe dev-icons are functionality though ;)).

The heterogenity of the the various aspects (issues, code reviews/PRs, CI/CD) requires a modular
structure to handle each aspect with a different "backend". The user interface _per aspect_ should
be the same across different git forges. The module/feature set per git forge/backend may differ.

### Issues

- [x] telescope integration for listing, previewing and selecting issues
- [x] "normal" issue interaction directly from `nvim`
    - editing title, description, labels, assignee
    - adding comments
    - closing/reopening issues (or state transitions in general)
- [ ] searching for issue by changing labels, assignees and so on interactively
- [x] a bit of convenience, e.g. providing a way to custom query only issues with specific labels (bugs)
- [ ]project, defined through path matching, specific options
- [ ] get both Github and GitLab working

### PRs

- [ ] Listing PRs, similar to issue listing
- [ ] Adjusting PRs
    - editing title, description, labels, assignees, reviewers
    - adding comments
    - showing CI information (is this green?)
    - completing the PR

## Far Goals

- "pinning" issues such that they are kept as local files and can be accessed all the time
- enabling offline work for issues
- navigating between issues, like following a referenced issue (almost a near goal)
- maybe notifications, but I personally don't like disturbances
    - e.g. getting new bugs may be useful for triage purposes
    - something like periodic update-queries and changes in results turn into notifications
    - knowing about new comments on a pinned issue is helpful when waiting for feedback
- opening pull requests, e.g. with [DiffView](https://github.com/sindrets/diffview.nvim)
    - maybe even commenting on individual changes a.k.a. Code Review Features
- some light project management tools, assigning issues to projects and stuff like that
- maybe a dashboard (you can use `gh status` already)
- maybe integration into [Neorg](https://github.com/nvim-neorg/neorg), like a summary in the index and navigation to the issues
- creating queues for changes done during offline work that would be synced back at the next
  possible occassion

## Stretch Goals

- maybe an LSP?
    - jumping to the issue, even if viewing the commit message in `neogit`
    - jumping between issues in general
    - providing suggestions for names

## Non-Goals

- providing advanced project management or development planning tools
- repository discovery through this plugin
- providing a user interface for CI/CD solutions - maybe debatable
    - the only relevant information in my opinion is "not started, in progress, failure/success"
    - on failure, the log messages would be great to gather, this might differ depending on the
      git forge and the level of integration of the CI/CD platform
- developing against raw APIs, this plugin should wrap `gh` like CLI tools you could use directly
    - extending existing tools with missing features is OK, but I won't do it
    - in the late stages of features, the last bit of information integration may need an API
      request, best case, the CLI tool in question already provides means for that
- parsing `git` repositories, please use a proper `git` plugin like [neogit](https://github.com/NeogitOrg/neogit)

## Motivation

I never developed a plugin for `nvim` and have no prior experience in `lua`. That will be reflected
in the code you may read :)
The plugin serves a personal wish for tighter integration of issue work into my personal `nvim`
workflow.
It is open for everyone to suggest improvements or maybe even implement them.
Given the hobby nature of the work, I will try to keep it focussed on my needs and preserve the
right to reject feature requests.
The development documents will hopefully help in communicating the project priorities.

Advice, help and suggestions are always welcome!

## Definition of Done

Version 1.0 is when I can perform day to day work with issues, pull requests and CI/CD interaction
with GitHub, Bitbucket (or GitLab) and Jira. Other git forges (especially if providing a CLI tool)
may be integrated but are second class citizens.
If anyone has stakes into something else, go ahead and support me :)
