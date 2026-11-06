# Adopt — take in something new: a dependency, a tool, a format, a channel

> Look before the install, not after. After the install the decision leans toward what is already there.
> The row below is a sample at strength C: derived by the authors of the kit, not decided by you. Edit it, promote it, or delete it.

<!-- toc:begin generated, do not edit by hand (run the toc command) -->
- AD01 | about to add a dependency or install an external tool | agent (the check and the write-up) / owner (the install) | C
<!-- toc:end -->

### AD01 — about to add a dependency or install an external tool

- **Rule**: First check whether the standard library or something already installed does the job. If it does not, write down the source, the maintainer, and what the tool can read and write, before anything is installed.
- **Decider**: agent (the check and the write-up) / owner (the install)
- **Strength**: C
- **Derived from**: an installed tool runs with the access of the session, and that access is granted at install time.
