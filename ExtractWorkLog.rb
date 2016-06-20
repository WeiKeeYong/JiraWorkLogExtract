require 'ostruct'
require 'openssl'
require 'json'
require 'tiny_tds'
require 'net/http'
require 'time'
##Calling connection files with the private data e.g. pw & users id
require_relative  '../../Private/JiraWorkLogExtract_connection'

## check if its a valid Json
def valid_json?(json)
  JSON.parse(json)
  true
rescue
  false
end

## Load JSON
def load_JSON_From_Web(url_link,login, password, use_ssl )
  uri = URI.parse(url_link)
  http = Net::HTTP.new(uri.host,uri.port)
  http.use_ssl = use_ssl
  request = Net::HTTP::Get.new(uri.request_uri)
  request.basic_auth login, password
  request['Content-Type'] = 'application/json'
  respond = http.request(request)
  (respond.code == "200") ? respond.body : respond.message
end

## True if you need to extract the worklog created on the start date.
Only_Worklogs_from_startDate = false

##Jira Login information
# Login = 'uesrid@domain.com'
# Password = 'yourpassword'
## Today Date.
Date_create = Time.now.iso8601
##The Start and Ending date want to extract the date use YYYY-MM-DD
start_date = Date.parse('2016-03-01')
end_date = Date.parse('2016-03-30')
date_counter = 0

while (start_date + date_counter) <= end_date
## Jira_restapi_url constant is the path to get your company jira issues, and the jql
# Jira_restapi_url = 'https://<yourcompany path>.atlassian.net/rest/api/2/search?jql=timeSpent+is+Not+EMPTY+'

##Filter Worklog is not empty
  query_string = '/search?jql=timeSpent+is+Not+EMPTY+'
##The Date range
  query_string  = query_string + 'AND+updated+>=+"' + (start_date + date_counter).to_s + '"+And+updated+<="' + (start_date + date_counter + 1).to_s + '"'
##Return the filed required
  query_string = query_string + '&fields=worklog,parent,updated,issuetype,summary,customfield_10008&maxResults=200'
  url = Jira_restapi_url + query_string
  return_body = load_JSON_From_Web(url,Login,Password,true)

  if valid_json?(return_body)

    return_json_object = JSON.parse(return_body,object_class: OpenStruct)
    issues_count = return_json_object.total
    issue_counter = 0
    worklog_data = Array.new

# get issue type, if sub-task need to get parent; and get Epic
    while issue_counter < issues_count
      parent_key = 'null'
      issue_key = return_json_object.issues[issue_counter].key
      issue_team = issue_key.split('-')[0]
      issue_type = return_json_object.issues[issue_counter].fields.issuetype.name
      epic_link = return_json_object.issues[issue_counter].fields.customfield_10008
      (epic_link.nil?) ? epic_link = 'null' : epic_link = "'" + epic_link + "'"
      issue_title = return_json_object.issues[issue_counter].fields.summary #issue title is actually issue summary inside Jira
      if issue_type.include? 'Sub-task'
        parent_key = "'" + return_json_object.issues[issue_counter].fields.parent.key + "'"
      else
        parent_key ="null"
      end

      ## get worklog counter, if > 20, need to call different rest API path

      worklog_total = return_json_object.issues[issue_counter].fields.worklog.total.to_i
      if worklog_total <= 20
        worklogs_object = return_json_object.issues[issue_counter].fields.worklog.worklogs
      else
        ## Need to add new function call to grab > 20 worklogs
        url_worklog = 'https://ibaselelong.atlassian.net/rest/api/2/issue/' + issue_key + '/worklog'
        return_worklog_body = load_JSON_From_Web(url_worklog,$Login,$Password,true)
        worklog_object = JSON.parse(return_worklog_body,object_class: OpenStruct)
        worklog_total = worklog_object.total.to_i
        worklogs_object = worklog_object.worklogs
      end
      ##put the worklogs into Array
      worklog_counter = 0
      while worklog_counter < worklog_total
        worklog_timeSpentHours = 0
        worklog_started = worklogs_object[worklog_counter].started
        worklog_timeSpentSeconds = worklogs_object[worklog_counter].timeSpentSeconds.to_i
        if !worklog_timeSpentSeconds.nil? && worklog_timeSpentSeconds > 0
          worklog_started = Time.parse(worklogs_object[worklog_counter].started)
          worklog_timeSpentHours = worklog_timeSpentSeconds / 3600.to_f
          worklog_user =  worklogs_object[worklog_counter].author.displayName
          worklog_id = worklogs_object[worklog_counter].id
        end
        worklog_created = Time.parse(worklogs_object[worklog_counter].created).to_date
        worklog_data << [issue_team  , issue_key  , issue_title , epic_link, issue_type  , parent_key, Date_create  , worklog_started.iso8601  ,worklog_user  ,worklog_timeSpentHours,worklog_id]  unless worklog_created <  (start_date + date_counter) && Only_Worklogs_from_startDate
        worklog_counter += 1
      end
      issue_counter += 1
    end

## this is call to insert data into db, passing array
    insert_to_db(worklog_data)
    date_counter += 1
  end



end
