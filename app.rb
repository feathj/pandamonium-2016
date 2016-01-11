require 'sinatra'
require 'set'
require 'json'
require 'byebug'

require 'redis'

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
    data = send("query_data_#{db}")

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

  def query_data_file
    country = params['country']
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
      # TODO: set value
      key = "#{row['LOCATION']}_#{row['TIME']}"
      @redis.set(key, {
        'country' => row['LOCATION'],
        'time' => row['TIME'],
        'value' => row['Value']
      }.to_json)
    end
    # TODO: set countries
    @redis.set('countries', countries.to_a.to_json)
  end

  def query_countries_redis
    # TODO: return countries
    @redis.get('countries')
    JSON.parse(@redis.get('countries'))
  end

  def query_data_redis
    country = params['country']
    data = []
    @redis.scan_each(match: "#{country}_*") do |key|
      data.push JSON.parse(@redis.get(key))
    end
    data
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

  run! if app_file == $0
end
