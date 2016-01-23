Pre-requisites
==============
This guide will assume that you have a working docker environment, and some experience with a relational database.  We
will be utilizing [dinghy](https://github.com/codekitchen/dinghy) on OSX.

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
We are going to be working with a dataset provided by the [OECD](https://data.oecd.org/). We will look at monthly
industrial production for all countries available.  This ends up being quite a few data records, so it will be a decent
use case.  We will see that some data technologies handle time series data sets better than others, and it will give us
an idea of which technologies make the most sense for a given application.

What we need to implement in our app
====================================
We are going to be exploring a few different database technologies, and we will need to implement three different ruby
methods per database in a simple sinatra app.

```
def load_*
  # 1. runs any required setup for database (create tables, indexes etc.)
  # 2. takes data from csv_data and saves countries to database (Note that only country code will be required eg 'USA')
  # 3. takes data from csv_data and saves datapoints to database. (country, time, and value will be required)
  # We will always clear data out before attempting to save to prevent duplicates
end

def query_countries_*
  # returns an array of country code strings extracted from csv_data and saved to database
  ["AUT","BEL","BRA","CAN","CHL","COL","CZE","DEU","DNK", ...]
end

def query_data_*(country)
  # given a country code as a string, returns an array of datapoint hashes
  [{"country":"CAN","time":"1961-01","value":"24.88589"},{"country":"CAN","time":"1961-02","value":"24.91095"}, ...]
end
```

I have implemented the flat file methods for your reference.  You will notice that the "load" routine is blank. This is
intentional, as the flat file implementation does not save to any database and will give us a good reference for
performance.

Running and debugging
=====================
To run this app simply run:
```
$ docker-compose pull
$ docker-compose build
$ docker-compose up
```
Open browser to: http://panda.docker/

Any code changes made to the app.rb file will require a restart of the app container.
```
$ docker-compose stop app
$ docker-compose start app
```

As part of this docker image, I have included the byebug gem.  Byebug doesn't work properly in the basic
`docker-compose up` scenario.  To actually hit a byebug breakpoint, do the following:
```
$ docker-compose stop app
$ docker-compose run --service-ports app
```
This will run the application container with service-ports, which enables proper tty and allows you to debug as normal.

Redis
=====
The first technology that we will implement is Redis.  Redis is a simple in memory key-value datastore.  It is generally
used as a caching layer, but with added persistence functionality, it is also used as a primary database in some
applications.

Key value stores are basically hash tables as a service HTAAS (not a real acronym).  You provide a string key, and they
give you a string value back.  It also has additional support for composite values (list of strings, set of strings,
hash of string to string), but we will just work with the basic string to string functionality for the purposes of this
workshop.

We will be using the [redis-rb](https://github.com/redis/redis-rb) driver for our interaction with Redis.  I have setup
the redis client in a variable named `@redis`.  This same convention will follow all technologies that we work with.

Here are some basic commands to familiarize yourself with:
```
@redis.set("mykey_1", "hello world 1")
@redis.set("mykey_2", "hello world 2")
@redis.get("mykey_1")

@redis.scan_each(match: "mykey_*").do |key|
  ...
end
```
Redis Implementation Notes
--------------------------
* Composite primary key
* JSON serialize and deserialize
* Scan for data query

Mongo
=====
Implementing our application in redis probably showed you some of the pain that you can encounter when trying to
structure / de-normalize your data to fit in a simple key-value store.  This is generally why redis is not used as a
primary data store unless the data being stored is extremely simplistic.  Don't write redis off though, it's
simplicity allows to be optimized in a way that complex DBMS's can't be.  Right tool, right job.

Next in line of our nosql evolution is Mongo.  Mongo is known as a "document based datastore".  Basically, it accepts
json (bson) payloads into "collections", that are assigned a primary key (unless one is provided), but since the documents are
a first class citizen, we can start to do things like query on fields other than the primary key.  Unlike redis, many
different native [data types](https://docs.mongodb.org/manual/reference/bson-types/) are supported.

Mongo was designed to be friendly to the developer, but maybe not quite as friendly to the devops engineer.  Getting
started is quite easy, but keeping it performant under heavy load with many records can be tricky.  Either way, it gives
us a great introduction to a data store with more structure and features.

We will be working with the official [mongo driver](https://docs.mongodb.org/ecosystem/tutorial/ruby-driver-tutorial/)

Some basics
```
@mongo[:collection_name].drop
# collections are implicitly created when insert occurs
@mongo[:collection_name].insert_one({'key1'=> 'val1', 'key2'=> 'val2'})
# mongo follows "query by example" convention, and creates implicit indexes on fields queried
@mongo[:collection_name].find('key1' => 'val1').each |record|
  ...
end
```

Mongo Implementation Notes
--------------------------
* Implicit creation of table (can be explicit if required)
* Implicit creation of indexes (can be explicit if required, which is often)
* Type inference on document fields (again, can be explicit)
* Elasticsearch, very similar, but amazing support for fuzzy searching on fields, less support for data-types, range
  queries etc.

Cassandra
=========
We will get back to a more modern document based datastore in a minute, but lets talk about column-oriented data.
Cassandra is basically a hybrid between a key-value database, and a tabular (or column-oriented) database.  Data records
are organized into rows and tables, and are queried via primary key.  No joins or explicit relationships are defined,
and records can only be queried by their primary key, unless an explicit index is created for a column in the table.
Tables are grouped into "keyspaces".

Operations on cassandra databases are generally executing using the SQL-like syntax called "CQL".  This helped with
adoption of the technology as a large majority of software engineers are comfortable with SQL.  We will be using the
official datastax ruby driver to interact with the data.

Some basics
```
session = @cassandra.connect('system')
session.execute('CREATE TABLE people(id INT, lastname VARCHAR, firstname VARCHAR, PRIMARY KEY(id))')

insert = session.prepare('INSERT INTO people(id, lastname, firstname) VALUES(?,?,?)')
session.execute(insert, arguments: [1, 'Featherstone', 'Jon')
session.execute(insert, arguments: [2, 'Featherstone', 'Luke')

select = session.prepare('SELECT * FROM people WHERE lastname = ?')
session.execute(select, arguments: ['featherstone']).each do |row|
  ...
end

Cassandra Implementation Notes
------------------------------


```

Rethink
=======

NewSQL
======

Graph DB
========

TODO
====
* Show timming information
