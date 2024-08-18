# Where is this Going?

In short, this plugin tries to provide access to
- issues
- pull requests
- CI/CD
for a variety of git forges, namely GitHub, GitLab, Jira (issues at least)/Bitbucket and maybe
Gitea. The user interface should be the same for the different git forges.

The day-to-day interactions should be as fast as possible and not distract the user.
Enabling at least basic offline work should be possible.

The plugin should be well documented and the code easy to read.

## Near Goals 

The goal of this plugin is to keep most daily developer interactions with the projects git forge
within `nvim`. Especially quick actions like assigning an issue or writing a comment should not
require a context switch to browser. It goes for functionality first, then customizability and
finally asthetics.
The heterogenity of the the various aspects (issues, code reviews/PRs, CI/CD) requires a modular
structure to handle each aspect with a different "backend". The user interface _per aspect_ should
be the same across different git forges. The module/feature set per git forge/backend may differ.

## Far Goals

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
- maybe simple time tracking or at least a way to add time taken to an issue
- creating queues for changes done during offline work that would be synced back at the next
  possible occassion

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
- parsing `git` repositories, please use a proper `git` plugin like [Neogit](https://github.com/NeogitOrg/neogit)

## Motivation

I never developed a plugin for `nvim` and have no prior experience in `Lua`. That will be reflected
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
with GitHub, Bitbucket and Jira. Other git forges (especially if providing a CLI tool) may be
integrated but are second class citizens. Why? Because I don't use them.
If anyone has stakes into something else, go ahead and support me :)

All features extending this base line may be developed at a much slower pace and may never
materialize "from my hand". They are nice to haves and I will certainly not stop anyone from
helping me out creating them. But I might not have the time and motiviation to do it myself.
