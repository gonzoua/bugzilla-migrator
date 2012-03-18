# Migrating GNATS PR Database to Bugzilla #

This repository tracks changes made to Bugzilla to support the FreeBSD GNATS Problem Reports database to Bugzilla.

## How to try it out: ##

### Required Software ###

First, you need to install:

* net/cvsup-mirror: make sure to select the GNATS PR database during post-install.
* devel/bugzilla: for obvious reasons.
* some version of either mysql, pgsql or oracle.

### Bugzilla Setup ###

We then want to configure our bugzilla instance. The source files won't be touched.

* Run checksetup.pl once (as root).
* Inform values in localconfig.
* Re-run checksetup.pl (as root). Your bugzilla setup should be complete.

### Checkout setup ###

* Clone this repository somewhere.
* Copy localconfig to your checkout.
* Run checksetup.pl as yourself, this should populate the ./data/ directory.
* Update values in ./data/migrate-Gnats.cfg to match your setup (you probably only want to change the gnats directory).
* Run the migrate.pl script, see it fail (or not).
* Fix and iterate.
