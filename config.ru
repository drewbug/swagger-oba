map '/' do
  use Rack::Static, 
    :urls => ["/images", "/js", "/css"],
    :root => "public",
    :index => 'index.html'

  run Rack::File.new("public")
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
