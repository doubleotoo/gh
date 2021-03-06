require 'gh'
require 'faraday'

module GH
  # Public: This class deals with HTTP requests to Github. It is the base Wrapper you always want to use.
  # Note that it is usually used implicitely by other wrapper classes if not specified.
  class Remote < Wrapper
    attr_reader :api_host, :connection, :headers, :prefix

    # Public: Generates a new Rempte instance.
    #
    # api_host - HTTP host to send requests to, has to include schema (https or http)
    # options  - Hash with configuration options:
    #            :token    - OAuth token to use (optional).
    #            :username - Github user used for login (optional).
    #            :password - Github password used for login (optional).
    #            :origin   - Value of the origin request header (optional).
    #            :headers  - HTTP headers to be send on every request (optional).
    #            :adapter  - HTTP library to use for making requests (optional, default: :net_http)
    #
    # It is highly recommended to set origin, but not to set headers.
    # If you set the username, you should also set the password.
    def setup(api_host, options)
      token, username, password = options.values_at :token, :username, :password

      api_host  = api_host.api_host if api_host.respond_to? :api_host
      @api_host = Addressable::URI.parse(api_host)
      @headers  = options[:headers].try(:dup)  || {
        "Origin"          => options[:origin] || "http://example.org",
        "Accept"          => "application/vnd.github.v3.raw+json," \
                             "application/vnd.github.beta.raw+json;q=0.5," \
                             "application/json;q=0.1",
        "Accept-Charset"  => "utf-8"
      }

      @prefix = ""
      @prefix << "#{token}@" if token
      @prefix << "#{username}:#{password}@" if username and password
      @prefix << @api_host.host

      faraday_options = {:url => api_host}
      faraday_options[:ssl] = options[:ssl] if options[:ssl]
      faraday_options.merge! options[:faraday_options] if options[:faraday_options]

      @connection = Faraday.new(faraday_options) do |builder|
        builder.request(:authorization, :token, token) if token
        builder.request(:basic_auth, username, password)  if username and password
        builder.request(:retry)
        builder.response(:raise_error)
        builder.adapter(options[:adapter] || :net_http)
      end
    end

    # Public: ...
    def inspect
      "#<#{self.class}: #{api_host}>"
    end

    # Public: Retrieves resources from Github.
    #
    # Examples
    #
    #   Github::Remote.new['users/rkh'] # => { ... }
    #
    # Raises Faraday::Error::ResourceNotFound if the resource returns status 404.
    # Raises Faraday::Error::ClientError if the resource returns a status between 400 and 599.
    # Returns the Response.
    def [](key)
      response = frontend.http(:get, path_for(key), headers)
      modify(response.body, response.headers)
    end

    # Internal: ...
    def http(verb, url, headers = {}, &block)
      connection.run_request(verb, url, nil, headers, &block)
    end

    # Internal: ...
    def request(verb, key, body = nil)
      response = frontend.http(verb, path_for(key), headers) do |req|
        req.body = Response.new({}, body).to_s if body
      end
      modify(response.body, response.headers)
    end

    # Public: ...
    def post(key, body)
      request(:post, key, body)
    end

    # Public: ...
    def delete(key)
      request(:delete, key)
    end

    # Public: ...
    def patch(key, body)
      request(:patch, key, body)
    end

    # Public: ...
    def put(key, body)
      request(:put, key, body)
    end

    # Public: ...
    def reset
    end

    # Public: ...
    def load(data)
      modify(data)
    end

    private

    def identifier(key)
      path_for(key)
    end

    def modify(body, headers = {})
      return body if body.is_a? Response
      Response.new(headers, body)
    end
  end
end
