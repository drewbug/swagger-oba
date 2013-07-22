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
    url = 'http://regions.onebusaway.org/regions.json'
    servers = JSON.parse(open(url).read)['data']['list']

    return servers
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
    oba_server = OBADirectory.retrieve.find { |x| x['regionName'] == oba_server_name}

    resources = {"apis" => []}
    resources["apis"] << {"path" => "/api-docs/where"} if oba_server['supportsObaDiscoveryApis'] || oba_server['supportsObaRealtimeApis']
    resources["apis"] << {"path" => "/api-docs/siri"} if oba_server['supportsSiriRealtimeApis']

    output = static.merge(resources)
    [200, {'Content-Type' => 'application/json'}, [output.to_json]]
  }
end

map '/api-docs/where' do
  run lambda { |env|
    where_file = JSON.parse File.read('api-docs/where')

    oba_server_name = Rack::Request.new(env).params['obaServer']
    oba_server = OBADirectory.retrieve.find { |x| x['regionName'] == oba_server_name}

    basepath = {"basePath" => "#{ oba_server['obaBaseUrl'] }api/where"}
    output = where_file.merge(basepath)

    obadiscovery_file = JSON.parse File.read('api-docs/obadiscovery')
    obarealtime_file = JSON.parse File.read('api-docs/obarealtime')

    output['apis'].concat(obadiscovery_file['apis']) if oba_server['supportsObaDiscoveryApis']
    output['apis'].concat(obarealtime_file['apis']) if oba_server['supportsObaRealtimeApis']

    [200, {'Content-Type' => 'application/json'}, [output.to_json]]
  }
end

map '/api-docs/siri' do
  run lambda { |env|
    siri_file = JSON.parse File.read('api-docs/siri')

    oba_server_name = Rack::Request.new(env).params['obaServer']
    oba_server = OBADirectory.retrieve.find { |x| x['regionName'] == oba_server_name}

    basepath = {"basePath" => "#{ oba_server['siriBaseUrl'] }siri"}

    output = siri_file.merge(basepath)
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

    request_line = "#{ env['REQUEST_METHOD'] } #{ env['REQUEST_URI'].sub(/\A\/proxy\/?/, '/') } #{ env['HTTP_VERSION'] }\r\n"

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
