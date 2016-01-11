Pre-requisites
==============
This guide will assume that you have a working docker environment, and some experience with a relational database.  We
will be utilizing (dinghy)[https://github.com/codekitchen/dinghy] on OSX.

History
=======
The term "database" came to be once disk storage was available for computers in the early 1960s.  Prior to this time,
tape based persistence drove application design to follow a more "batch processing" type model.  Direct access to disk
allowed software engineers to write and read data relatively quickly creating a whole new world of what was possible in
software.

Navigational Databases
======================
Early database systems were mainly filesystem based home grown solutions loosely known as 'navigational databases'.  You
could imagine creating a scheme where a directory could represent a "table", and a filename could represent primary key
of a particular record like so:

`/db/teachers/3`  
`/db/students/244`

*Contents of db/students/244*
```
student_record
sid=244
ssn=555-55-5555
lastname=featherstone
firstname=jonathan
major=cs
```

Lookup for the record is as simple as attempting to load the file based on ID, but there are Obvious problems and
limitations with this approach.  Lookup by anything other than primary key results in a "scan".  Literally looping over
every file in the folder, parsing it, loading it into memory, and checking the desired field for the value.  This has
obvious performance problems.

To deal with this problem, primitive data indexing systems were developed.  Indexing is the process of creating a
reference to a record through an "indexed" field in the record.  For unique values (values that are unique to the
record) the implementation could be as simple as creating a new file in an index specific folder that symlinks to the
original record. Something like this:

`/db/students/ssn_index/333-33-3333 -> ../243`  
`/db/students/ssn_index/555-55-5555 -> ../244`

Lookup for a record by ssn would be as simple as attempting to load the symlinked file in the `ssn_index` folder.  This
methodology would obviously only work on unique fields.  Non-unique fields would have relied on a slightly more complex
indexing scheme.  Maybe something like this:

`/db/students/major_index/english`
`/db/students/major_index/cs`

*Contents of db/students/major_index/cs*
```
index_record
244
256
151
...
```

Lookup for records by major would be as simple as querying the index file, loading all of the records referenced, and
returning them to the user.  Any further filtering of records could be done in a scan type routine after the index
values were loaded.

Keep in mind, that in practice, the systems weren't implemented exactly this way (people much smarter than myself
designed them and figured out neat optimizations), but the basic principles described here are correct.

Increases in the complexity of desired features, and the need for data portability between systems drove the
standardization of the database layer into what became known as Database Management Systems.  Applications could now
be implemented on a standardized data model that would manage creation, retrieval, update and deletion of data, managing
all updating to indexes required.

Relational Databases
=====================
In many software systems, the relationship between data records is important, and added functionality to describe
relationships, ensure referential integrity, and optimize speed of pulling related records became very important.
Building on the foundation of navigational DBMS, so called "relational databases" started to become quite prominent.

With the addition of relational features, the continued decrease in cost of storage media, additional functionality
to handle data read / write concurrency (multi-user environment), and standardization of an RDBMS query language (sql),
a critical mass of sorts was achieved with database technologies.  Applications that relied on home-brewed navigational
systems were almost entirely ported over to new RDBMS systems, and software data persistence and reporting evolved
rapidly.

For a very long period of time, pretty much all data persistence required in client / server architecture was
implemented using RDBMSs.  The word "database" became synonymous with "RDBMS" and "SQL"  The idea that any other db
architecture type was possible was mostly forgotten (simmilar to object oriented programming).

"NoSQL, NewSQL, NoDB" databases
===============================
The next generation of post-relational databases were known as "NoSQL" databases.  The title "NoSQL" was mainly used to
clearly differentiate that the particular technology is non-relational, non-SQL.  Since relation databases had become
so prevalent, the somewhat provocative and negative "no" prefix probably helped the technologies to gain traction, but
they probably tarnished the reputation of relational databases, and put a blanket term over many very different
technologies.

Let's discuss and work with some different database technologies in order of their relative complexity to see what the
fuss is all about.

Quick aside about data
======================
We are going to be working with a dataset provided by the OECD.  https://data.oecd.org/ We will look at monthly
industrial production for all countries available.  This ends up being quite a few data records, so it will be a decent
use case.  We will see that some data technologies handle time series data sets better than others, and it will give us
an idea of which technologies make the most sense for a given application.


Redis
=====
Redis is a simple in memory key-value datastore.  It is generally used as a caching layer, but with added persistence
functionality, it is also used as a primary database.

Key value stores are basically hash tables as a service HTAAS (not a real acronym).  You provide a string key, and they
give you a string value back.  It also has additional support for composite values (list of strings, set of strings,
hash of string to string)

Let's load up a redis db!

We have three calls that we will implement for each data source TODODODODODODODODODO


TODO
====
* Show actual graph
* Implement a few technologies
* Why does sinatra start again when killed?
* Slides

`docker-compose stop app`
`docker-compose run --service-ports app`

Possible Technologies
=====================
* Postgres
* Elasticsearch
* Cassandra
* DynamoDB
* Redis
* RethinkDB
* MongoDB

Bonus: graphdb
* neo4j