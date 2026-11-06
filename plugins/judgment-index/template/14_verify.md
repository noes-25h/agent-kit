# Verify — decide whether something can be called done, true, or absent

> Written is not done. Zero hits is not absence.
> The rows below are samples at strength C: derived by the authors of the kit, not decided by you. Edit them, promote them, or delete them.

<!-- toc:begin generated, do not edit by hand (run the toc command) -->
- VF01 | about to say that something is done | agent (reversible only) | C
- VF02 | a search or a check came back with zero results | agent (reversible only) | C
<!-- toc:end -->

### VF01 — about to say that something is done

- **Rule**: Run it and read the output first. Report what was run and what came out. When it could not be run, say "written, not run".
- **Decider**: agent (reversible only)
- **Strength**: C
- **Derived from**: a claim of completion that was not observed moves the checking to the owner.

### VF02 — a search or a check came back with zero results

- **Rule**: Before the zero is trusted, run the same search on a case that is known to contain a hit. Report the zero together with that control.
- **Decider**: agent (reversible only)
- **Strength**: C
- **Derived from**: a broken search and an empty result look the same from the outside.
