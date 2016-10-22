PROJECT = cduck

$(PROJECT): 
	cat README.1st
users:	
	setup/instusers.pl

install:
	setup/instbin.pl

conf:
	setup/nodeconfig.pl

fetch: 
	/usr/local/capibara/cduck/bin/capcron.pl

save:
	/bin/cp /usr/local/capibara/cduck/etc/cduc*conf backup/
	/bin/cp /usr/local/capibara/security/etc/tids.conf backup/

rest:
	/bin/cp backup/tids.conf /usr/local/capibara/security/etc/tids.conf
	/bin/cp backup/cduc*conf /usr/local/capibara/cduck/etc/

full-install:	users install conf fetch containment
 
reinstall:	save uninstall install rest fetch 

containment:
	setup/containment.pl

uninstall:
	dyn/idscleanup.sh

