# CURSE (Collection of Useful Reaper Scripts and Enhancements)

## User Documentation

For the documentation of the project and each and every script, go to the [User Documentation]() hosted online (also available in markdown format in this repo under `Docs`).

## Development Documentation

### Environment

We use a nix-shell to set up our dev environment with Ruby and some additional packages to build native extensions that some Gems require. Why Ruby? It allows us to use Jekyll to preview the documentation as it will be pushed to GitHub Pages from the `Docs` subdirectory of this repo. Coincidentally, reapack-index is also a Ruby Gem, so we kill two birds with one stone. Thanks, Cfillion! :D