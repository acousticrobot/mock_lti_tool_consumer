require 'sinatra'
require 'ims/lti'
require 'digest/md5'
# must include the oauth proxy object
require 'oauth/request_proxy/rack_request'
require 'pp'

enable :sessions

get '/' do
  @message = params['message']
  @username = session['username']
  erb :tool_config
end

post '/tool_launch' do
  if %w{tool_name launch_url consumer_key consumer_secret}.any?{|k|params[k].nil? || params[k] == ''}
    redirect to('/tool_config?message=Please%20set%20all%20values')
    return
  end

  tc = IMS::LTI::ToolConfig.new(:title => params['tool_name'], :launch_url => params['launch_url'])
  tc.set_custom_param('message_from_sinatra', 'hey from the sinatra example consumer')
  @consumer = IMS::LTI::ToolConsumer.new(params['consumer_key'], params['consumer_secret'])
  @consumer.set_config(tc)

  host = request.scheme + "://" + request.host_with_port

  @consumer.context_id = RESOURCE_LINK
  @consumer.context_label = CONTEXT_LABEL
  @consumer.context_title = CONTEXT_TITLE
  @consumer.launch_presentation_return_url = host + '/tool_return'
  @consumer.lis_course_offering_sourcedid = LIS_COURSE_OFFERING_SOURCEDID
  @consumer.lis_person_contact_email_primary = LIS_PERSON_CONTACT_EMAIL_PRIMARY
  @consumer.lis_person_name_family = FAMILY_NAME
  @consumer.lis_person_name_full = FULL_NAME
  @consumer.lis_person_name_given = GIVEN_NAME
  @consumer.lis_person_sourcedid = LIS_PERSON_SOURCEDID
  @consumer.resource_link_id = RESOURCE_LINK
  @consumer.resource_link_title = RESOURCE_LINK_TITLE
  @consumer.roles = "Instructor"
  @consumer.tool_consumer_info_product_family_code = TOOL_CONSUMER_INFO_PRODUCT_FAMILY_CODE
  @consumer.tool_consumer_info_version = "cloud"
  @consumer.tool_consumer_instance_contact_email = "notifications@instructure.com"
  @consumer.tool_consumer_instance_guid = "7db438071375c02373713c12c73869ff2f470b68.umich.instructure.com"
  @consumer.tool_consumer_instance_name = "University of Michigan"
  @consumer.user_id = USER_ID
  @consumer.user_image = "https://secure.gravatar.com/avatar/example.png"

  if params['assignment']
    @consumer.lis_outcome_service_url = host + '/grade_passback'
    @consumer.lis_result_sourcedid = "oi"
  end

  @autolaunch = !!params['autolaunch']

  erb :tool_launch
end

get '/tool_return' do
  @error_message = params['lti_errormsg']
  @message = params['lti_msg']
  puts "Warning: #{params['lti_errorlog']}" if params['lti_errorlog']
  puts "Info: #{params['lti_log']}" if params['lti_log']

  erb :tool_return
end

post '/grade_passback' do
  # Need to find the consumer key/secret to verify the post request
  # If your return url has an identifier for a specific tool you can use that
  # Or you can grab the consumer_key out of the HTTP_AUTHORIZATION and look up the secret
  # Or you can parse the XML that was sent and get the lis_result_sourcedid which
  # was set at launch time and look up the tool using that somehow.

  req = IMS::LTI::OutcomeRequest.from_post_request(request)
  sourcedid = req.lis_result_sourcedid

  # todo - create some simple key management system
  consumer = IMS::LTI::ToolConsumer.new('test', 'secret')

  if consumer.valid_request?(request)
    if consumer.request_oauth_timestamp.to_i - Time.now.utc.to_i > 60*60
      throw_oauth_error
    end
    # this isn't actually checking anything like it should, just want people
    # implementing real tools to be aware they need to check the nonce
    if was_nonce_used_in_last_x_minutes?(consumer.request_oauth_nonce, 60)
      throw_oauth_error
    end

    res = IMS::LTI::OutcomeResponse.new
    res.message_ref_identifier = req.message_identifier
    res.operation = req.operation
    res.code_major = 'success'
    res.severity = 'status'

    if req.replace_request?
      res.description = "Your old score of 0 has been replaced with #{req.score}"
    elsif req.read_request?
      res.description = "You score is 50"
      res.score = 50
    elsif req.delete_request?
      res.description = "You score has been cleared"
    else
      res.code_major = 'unsupported'
      res.severity = 'status'
      res.description = "#{req.operation} is not supported"
    end

    headers 'Content-Type' => 'text/xml'
    res.generate_response_xml
  else
    throw_oauth_error
  end
end

def throw_oauth_error
  response['WWW-Authenticate'] = "OAuth realm=\"http://#{request.env['HTTP_HOST']}\""
  throw(:halt, [401, "Not authorized\n"])
end

def was_nonce_used_in_last_x_minutes?(nonce, minutes=60)
  # some kind of caching solution or something to keep a short-term memory of used nonces
  false
end
