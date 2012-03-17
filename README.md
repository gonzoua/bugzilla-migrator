This repository tracks changes made to Bugzilla to support the FreeBSD GNATS Problem Reports database to Bugzilla.

How to try it out:

First you need to install:
- net/cvsup-mirror: make sure to select the GNATS PR database during post-install.
- devel/bugzilla: for obvious reasons.
- some version of either mysql, pgsql or oracle.

Setup bugzilla:
- Run checksetup.pl once (as root).
- Inform values in localconfig.
- Re-run checksetup.pl (as root). Your bugzilla setup should be complete.

Setup your checkout:
- Clone this repository somewhere.
- Copy localconfig to your checkout.
- Run checksetup.pl as yourself, this should create the ./data/ directory.
- Run perl migrate.pl --from=gnats --verbose 2>&1 | tee /tmp/migrate.log, this will create a default ./data/migrate-Gnats.cfg.
- Update values in ./data/migrate-Gnats.cfg to match your setup (you probably only want to change the gnats directory).
- Re-run the migrate.pl script, see it fail (or not).
- Fix.
