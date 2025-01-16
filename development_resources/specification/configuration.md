# Spec: Configuration

The configuration of the plugin should provide sensible defaults and allow for different
configurations of different projects. Configuration is hierarchical in nature.
The most specific level of configuration takes precedence over the next higher level. These are:
1. plugin provided defaults
1. user provided settings
1. project provided settings
1. action/view provided settings

## Requirements

### Necessities

- configurations must follow the hierarchical structure, the most specific definition takes
  precedence over the next higher level
- project level configuration is determined based on matching of the current execution directory
  (`:cd` in `nvim`) with most specific project match
- using relative paths to make the structure machine independent shall be supported
- configuration options are documented
- configuration options are general and not specific to a specific git forge
    - the naming might take inspiration from one, most likely `gh`
- git forge specific options are in a separate section under the key of the git forge in use

### Nice to Have

- can't think of anything right now

## Non-Functional Requirements

- using the plugin should not require a lot of effort
    - using only `GitHub` for repositories should not require any configuration at all ?!
- configuration should allow machine independence, especially the project matching is sensitive on
  this front
- it should be less involved than `Neorg`

## Customizations

- configuration should not be customizable in itself, but provide the customization endpoints
