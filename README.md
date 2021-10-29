# AppVolumesReplication
 Repositiry for AppVolumesReplication 

# Getting Started
Below are the instructions for setting up the AppVolumes Replication Script

# Pre-Requisites
Must have Pure storage setup at both target and destination sites. If you are not using pure you can rip out the pure storage parts and do your own replication.

In pure you must have Protection Group Setup. Have tested this with Asyc replication of storage LUN from one site to another using snapshots. 
Setup Instructions:
https://blog.purestorage.com/purely-technical/setting-up-flasharray-active-active-replication-activecluster/

You will need a LUN that will be used as a replication lun. This lun will be the same at both sites. Perfrably named the same. 

On top of Asysnc Replication being setup you will need to have two AppVolumes environments setup. And in order to have the Replication of the data to work, you must have storage groups setup in appvolumes. Storage Group at source site to copy data to Replication lun and Storage Group at destination site. The storage group at destination site has to be setup with Automatic Storage Selection. So it will auto add the replication lun to the Stroage group. 
