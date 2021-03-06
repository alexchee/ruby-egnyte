module Egnyte
  class Session

    attr_accessor :domain, :api

    def initialize(opts, strategy=:implicit, backoff=0.5)

      @strategy = strategy # the authentication strategy to use.
      raise Egnyte::UnsupportedAuthStrategy unless @strategy == :implicit
      
      @backoff = backoff # only two requests are allowed a second by Egnyte.
      @api = 'pubapi' # currently we only support the public API.

      # the domain of the egnyte account to interact with.
      raise Egnyte::DomainRequired unless @domain = opts[:domain]

      @client = OAuth2::Client.new(opts[:key], nil, {
        :site => "https://#{@domain}.egnyte.com",
        :authorize_url => "/puboauth/token"
      })

      @access_token = OAuth2::AccessToken.new(@client, opts[:access_token]) if opts[:access_token]
    end

    def authorize_url(redirect_uri, params ={})
      params.merge!(:redirect_uri => redirect_uri)
      @client.implicit.authorize_url(params)
    end

    def create_access_token(token)
      @access_token = OAuth2::AccessToken.new(@client, token) if @strategy == :implicit
    end

    def get(url, return_parsed_response=true)
      uri = URI.parse(url)
      request = Net::HTTP::Get.new( uri.request_uri )
      resp = request( uri, request, return_parsed_response )
    end

    def delete(url, return_parsed_response=true)
      uri = URI.parse(url)
      request = Net::HTTP::Delete.new( uri.request_uri )
      resp = request( uri, request, return_parsed_response )
    end

    def post(url, body, return_parsed_response=true)
      uri = URI.parse(url)
      request = Net::HTTP::Post.new(uri.request_uri)
      request.body = body
      request.content_type = "application/json"
      resp = request(uri, request, return_parsed_response)
    end

    def multipart_post(url, filename, data, return_parsed_response=true)
      uri = URI.parse(url)

      request = Net::HTTP::Post.new(uri.request_uri)
      request.body = data.read
      request.content_type = 'application/binary'

      resp = request(uri, request, return_parsed_response)
    end

    # perform a streaming download of a file
    # rather than in-memory.
    def streaming_download(url, opts)
      params = {
        :content_length_proc => opts[:content_length_proc],
        :progress_proc => opts[:progress_proc],
        'Authorization' => "Bearer #{@access_token.token}"
      }
      
      open(url, params)
    end

    private

    def request(uri, request, return_parsed_response=true)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.ssl_version = :SSLv3
      #http.set_debug_output($stdout)
      
      request.add_field('Authorization', "Bearer #{@access_token.token}")

      response = http.request(request)

      # Egnyte throttles requests to
      # two requests per second.
      sleep(@backoff)

      parsed_response = parse_response( response.code.to_i, response.body )
      return_parsed_response ? parsed_response : response
    end

    def parse_response( status, body )

      begin
        parsed_body = JSON.parse(body)
      rescue
        parsed_body = {}
      end

      # Handle known errors.
      case status
      when 400
        raise BadRequest.new(parsed_body)
      when 401
        raise NotAuthorized.new(parsed_body)
      when 403
        raise InsufficientPermissions.new(parsed_body)
      when 404
        raise FileFolderNotFound.new(parsed_body)
      when 405
        raise FileFolderDuplicateExists.new(parsed_body)
      when 413
        raise FileSizeExceedsLimit.new(parsed_body)
      end

      # Handle all other request errors.
      raise RequestError.new(parsed_body) if status >= 400

      parsed_body
    end

  end
end
