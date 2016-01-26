require 'sinatra/base'
require 'set'
require 'json'
require 'byebug'

require 'redis'
require 'mongo'
require 'cassandra'
require 'rethinkdb'

include RethinkDB::Shortcuts

class WebApp < Sinatra::Base
  # Config ############################################################
  configure do
    set :bind, '0.0.0.0'
    set :server, 'thin'
  end

  # Setup all connections #############################################
  before do
    # Redis
    @redis = Redis.new(
      host: 'redis',
      port: 6379
    )
    # Mongo
    @mongo = Mongo::Client.new('mongodb://mongo:27017/panda')
    # Cassandra
    @cassandra = Cassandra.cluster(hosts: 'cassandra')
    # Rethink
    @rethink = r.connect(host: 'rethink', port: 28015)
  end

  # Default route #####################################################
  get '/' do
    File.read(File.join('public', 'index.html'))
  end

  # Primary Routes ####################################################
  # load in whatever shape wanted, but note requirements below
  get '/load' do
    db = params['db']
    send("load_#{db}")
  end

  # must return array of country codes in json
  # ["SWE", "TUR", "GBR", "USA", "BRA"]
  get '/query_countries' do
    db = params['db']
    countries = send("query_countries_#{db}")

    content_type :json
    countries.sort.to_json
  end

  # given "country" code param, return array of datapoints with
  # following format
  # { "country": "USA", "time": "1966-01", "value": "50.04211" }
  get '/query_data' do
    db = params['db']
    country = params['country']
    data = send("query_data_#{db}", country)

    content_type :json
    data.sort{ |x,y| x['time'] <=> y['time']}.to_json
  end

  # Flat File #########################################################
  def load_file
  end

  def query_countries_file
    countries = Set.new
    csv_data.each do |row|
      countries.add row['LOCATION']
    end
    countries.to_a
  end

  def query_data_file(country)
    data = []
    csv_data.each do |row|
      if row['LOCATION'] == country
        data.push({
          'country' => row['LOCATION'],
          'time' => row['TIME'],
          'value' => row['Value']
        })
      end
    end
    data
  end

  # Redis #############################################################
  def load_redis
    countries = Set.new
    csv_data.each do |row|
      countries.add(row['LOCATION'])
      key = "#{row['LOCATION']}_#{row['TIME']}"
      @redis.set(key, {
        'country' => row['LOCATION'],
        'time' => row['TIME'],
        'value' => row['Value']
      }.to_json)
    end
    @redis.set('countries', countries.to_a.to_json)
  end

  def query_countries_redis
    @redis.get('countries')
    JSON.parse(@redis.get('countries'))
  end

  def query_data_redis(country)
    datapoints = []
    @redis.scan_each(match: "#{country}_*") do |key|
      datapoints.push JSON.parse(@redis.get(key))
    end
    datapoints
  end

  # Mongo #############################################################
  def load_mongo
    @mongo[:countries].drop
    @mongo[:datapoints].drop

    countries = Set.new
    csv_data.each do |row|
      countries.add(row['LOCATION'])
      @mongo[:datapoints].insert_one({
        'country' => row['LOCATION'],
        'time' => row['TIME'],
        'value' => row['Value']
      })
    end
    countries.to_a.each do |country|
      @mongo[:countries].insert_one({
        'country' => country
      })
    end
  end

  def query_countries_mongo
    countries = []
    @mongo[:countries].find.each do |country|
      countries.push(country['country'])
    end
    countries
  end

  def query_data_mongo(country)
    @mongo[:datapoints].find('country' => country).to_a
  end

  # Cassandra ########################################################R
  def load_cassandra
    session = @cassandra.connect('system')
    session.execute('DROP KEYSPACE IF EXISTS panda')
    session.execute("CREATE KEYSPACE panda WITH replication = {'class': 'SimpleStrategy','replication_factor': 3}")
    session = @cassandra.connect('panda')
    session.execute('CREATE TABLE countries(country VARCHAR, PRIMARY KEY(country))')
    session.execute('CREATE TABLE datapoints(id VARCHAR, country VARCHAR, time VARCHAR, value FLOAT, PRIMARY KEY(id))')
    session.execute('CREATE INDEX idx_datapoints_country ON datapoints (country);')

    countries = Set.new
    insert = session.prepare('INSERT INTO datapoints(id, country, time, value) VALUES(?,?,?,?)')
    csv_data.each do |row|
      countries.add(row['LOCATION'])
      key = "#{row['LOCATION']}_#{row['TIME']}"
      session.execute(insert, arguments: [key, row['LOCATION'], row['TIME'], row['Value'].to_f])
    end
    insert = session.prepare('INSERT INTO countries(country) VALUES(?)')
    countries.to_a.each do |country|
      session.execute(insert, arguments: [country])
    end
  end

  def query_countries_cassandra
    countries = []
    session = @cassandra.connect('panda')
    session.execute('SELECT * FROM countries').each do |row|
      countries.push(row['country'])
    end
    countries
  end

  def query_data_cassandra(country)
    datapoints = []
    session = @cassandra.connect('panda')
    select = session.prepare('SELECT * FROM datapoints WHERE country = ?')
    session.execute(select, arguments: [country]).each do |row|
      datapoints.push(
        'country' => row['country'],
        'time' => row['time'],
        'value' => row['value']
      )
    end
    datapoints
  end

  # Rethink ###########################################################
  def load_rethink
    r.db_drop('panda').run(@rethink) rescue nil # don't hate me Tina :(
    r.db_create('panda').run(@rethink)
    r.db('panda').table_create('countries', primary_key: 'country').run(@rethink)
    r.db('panda').table_create('datapoints', primary_key: 'id').run(@rethink)
    r.db('panda').table('datapoints').index_create('country').run(@rethink)

    countries = Set.new
    batch = []
    csv_data.each do |row|
      countries.add(row['LOCATION'])
      key = "#{row['LOCATION']}_#{row['TIME']}"
      batch.push({
        id: key,
        country: row['LOCATION'],
        time: row['TIME'],
        value: row['Value']
      })
      if batch.length > 200
        r.db('panda').table('datapoints').insert(batch).run(@rethink)
        batch.clear
      end
    end
    r.db('panda').table('datapoints').insert(batch).run(@rethink) if batch.length > 0
    countries.each do |country|
      r.db('panda').table('countries').insert({
        country: country
      }).run(@rethink)
    end
  end

  def query_countries_rethink
    r.db('panda').table('countries')['country'].coerce_to('array').run(@rethink)
  end

  def query_data_rethink(country)
    r.db('panda').table('datapoints').index_wait('country').run(@rethink)
    r.db('panda').table('datapoints').get_all(country, index: 'country').coerce_to('array').run(@rethink)
  end

  # Helpers ###########################################################
  def csv_header(header_line)
    # Some weird UTF-8 invisible chars here
    vals = header_line.split(',')
    vals.map do |e|
      e.strip.delete('"')
        .encode(Encoding.find('ASCII'), invalid: :replace, undef: :replace, replace: '')
    end
  end

  def csv_line_to_row(header, line)
    row_data = line.split(',')
    header.each_with_object({}).with_index do |(val, row), index|
      if row_data[index]
        row[val] = row_data[index].strip.delete('"') if row_data[index]
      else
        row[val] = nil
      end
    end
  end

  def csv_data
    # "LOCATION","INDICATOR","SUBJECT","MEASURE","FREQUENCY","TIME","Value","Flag Codes"
    # we do this by hand because the csv format is super wonky and I can't figure out how
    # to ruby
    header = nil
    data = []
    File.open('/app/data/industrial_production.csv', 'r:UTF-8').each_line do |line|
      if header
        row = csv_line_to_row(header, line)
        data.push row if row['FREQUENCY'] == 'M' # grab only monthly data for now
      else
        header = csv_header(line)
      end
    end
    data
  end
end

WebApp.run!