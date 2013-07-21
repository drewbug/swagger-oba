require 'json'
require 'open-uri'

class String
  def to_bool
    case self
    when 'TRUE'
      return true
    when 'FALSE'
      return false
    else
      return nil
    end
  end
end

module OBADirectory
  def self.retrieve
    url = 'http://spreadsheets.google.com/feeds/list/0AvybitaYFhhOdGpkNWEyY29ldjBtOHZ6UkVXcm9weEE/od6/public/values?alt=json'
    json = JSON.parse(open(url).read)['feed']['entry']

    return json.map do |server|
      { regionname: server["gsx$regionname"]["$t"],
        active: server["gsx$active"]["$t"].to_bool,
        obabaseurl: server["gsx$obabaseurl"]["$t"],
        siribaseurl: server["gsx$siribaseurl"]["$t"],
        supportsobadiscoveryapis: server["gsx$supportsobadiscoveryapis"]["$t"].to_bool,
        supportsobarealtimeapis: server["gsx$supportsobarealtimeapis"]["$t"].to_bool,
        supportssirirealtimeapis: server["gsx$supportssirirealtimeapis"]["$t"].to_bool}
    end
  end
end

map '/' do
  use Rack::Static, 
    :urls => ["/images", "/js", "/css"],
    :root => "public",
    :index => 'index.html'

  run Rack::File.new("public")
end

map '/api-docs.json' do
  run lambda { |env|
    static = {"swaggerVersion" => "1.1"}

    oba_server_name = Rack::Request.new(env).params['obaServer']
    oba_server = OBADirectory.retrieve.find { |x| x[:regionname] == oba_server_name}

    resources = {"apis" => []}
    resources["apis"] << {"path" => "/api-docs/obadiscovery"} if oba_server[:supportsobadiscoveryapis]
    resources["apis"] << {"path" => "/api-docs/obarealtime"} if oba_server[:supportsobarealtimeapis]
    resources["apis"] << {"path" => "/api-docs/sirirealtime"} if oba_server[:supportssirirealtimeapis]

    output = static.merge(resources)
    [200, {'Content-Type' => 'application/json'}, [output.to_json]]
  }
end

map '/api-docs/obadiscovery' do
  run lambda { |env|
    file = JSON.parse File.read('api-docs/obadiscovery')

    oba_server_name = Rack::Request.new(env).params['obaServer']
    oba_server = OBADirectory.retrieve.find { |x| x[:regionname] == oba_server_name}

    basepath = {"basePath" => "#{ oba_server[:obabaseurl] }where"}

    output = file.merge(basepath)
    [200, {'Content-Type' => 'application/json'}, [output.to_json]]
  }
end

map '/api-docs/obarealtime' do
  run lambda { |env|
    file = JSON.parse File.read('api-docs/obarealtime')

    oba_server_name = Rack::Request.new(env).params['obaServer']
    oba_server = OBADirectory.retrieve.find { |x| x[:regionname] == oba_server_name}

    basepath = {"basePath" => "#{ oba_server[:obabaseurl] }where"}

    output = file.merge(basepath)
    [200, {'Content-Type' => 'application/json'}, [output.to_json]]
  }
end

map '/api-docs/sirirealtime' do
  run lambda { |env|
    file = JSON.parse File.read('api-docs/sirirealtime')

    oba_server_name = Rack::Request.new(env).params['obaServer']
    oba_server = OBADirectory.retrieve.find { |x| x[:regionname] == oba_server_name}

    basepath = {"basePath" => "#{ oba_server[:siribaseurl] }siri"}

    output = file.merge(basepath)
    [200, {'Content-Type' => 'application/json'}, [output.to_json]]
  }
end

map '/index.html' do
  run lambda { |env|
    [302, {'Location' => '/'}, []]
  }
end

map '/proxy' do
  run lambda { |env|
    crossdomain = env['HTTP_CROSSDOMAIN']

    request_line = "#{ env['REQUEST_METHOD'] } #{ env['REQUEST_PATH'].sub(/\A\/proxy\/?/, '/') } #{ env['HTTP_VERSION'] }\r\n"

    headers = env.reject{|x| x[0..4] != 'HTTP_'}
    headers.delete('HTTP_VERSION')
    headers.delete('HTTP_CROSSDOMAIN')
    raw_headers = headers.map do |k, v|
      "#{k.sub(/\AHTTP_/, '')}: #{v}\r\n"
    end.join

    body = env['rack.input'].read(env['CONTENT_LENGTH'].to_i)

    request_string = request_line
    request_string += raw_headers
    request_string += "\r\n"
    request_string += body

    env['rack.hijack'].call
    begin
      res_socket = env['rack.hijack_io']
      req_socket = TCPSocket.new(crossdomain.split(':')[0], crossdomain.split(':')[1] || 80)

      req_socket.write(request_string)
      req_socket.close_write

      res_socket.write(req_socket.read)
    ensure
      req_socket.close
      res_socket.close
    end
    return [203, [], []]
  }
end
