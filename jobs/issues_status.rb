require 'json'
require 'time'
require 'dashing'
require 'active_support/core_ext'
require File.expand_path('../../lib/helper', __FILE__)

SCHEDULER.every '1h', :first_in => '1s' do |job|
	if ENV['GOOGLE_KEY']
		backend = BigQueryBackend.new(
			:keystr=>ENV['GOOGLE_KEY'],
			:secret=>ENV['GOOGLE_SECRET'],
			:issuer=>ENV['GOOGLE_ISSUER'],
			:project_id=>ENV['GOOGLE_PROJECT_ID']
		)
		result = backend.issue_count_by_status(
			:period=>'month', 
			:orgas=>(ENV['ORGAS'].split(',') if ENV['ORGAS']), 
			:repos=>(ENV['REPOS'].split(',') if ENV['REPOS']),
			:since=>ENV['SINCE']
		)
		data = result.data
		series = [[],[]]
		data['rows'].each do |row,i|
			# Cols: period, count_opened, count_closed
			period = Time.strptime(row['f'][0]['v'], '%Y-%m')
			series[0] << {x: period.to_i,y: row['f'][1]['v'].to_i}
			series[1] << {x: period.to_i,y: row['f'][2]['v'].to_i}
		end	
	else
		backend = GithubBackend.new()
		issues = backend.issue_count_by_status(
			:orgas=>(ENV['ORGAS'].split(',') if ENV['ORGAS']), 
			:repos=>(ENV['REPOS'].split(',') if ENV['REPOS']),
			:since=>ENV['SINCE']
		)
		series = [[],[]]
		issues.group_by_month(ENV['SINCE'].to_datetime).each do |period,issues_by_period|
			timestamp = Time.strptime(period, '%Y-%m').to_i
			series[0] << {
				x: timestamp,
				y: issues_by_period.select {|issue|issue.key == 'open'}.count
			}
			series[1] << {
				x: timestamp,
				y: issues_by_period.select {|issue|issue.key == 'closed'}.count
			}
		end
	end
	
	opened = series[0][-1][:y] rescue 0
	closed = series[1][-1][:y] rescue 0
	opened_prev = series[0][-2][:y] rescue 0
	closed_prev = series[1][-2][:y] rescue 0
	trend_opened = GithubDashing::Helper.trend_percentage_by_month(opened_prev, opened)
	trend_closed = GithubDashing::Helper.trend_percentage_by_month(closed_prev, closed)
	trend_class = GithubDashing::Helper.trend_class(trend_opened)
	
	send_event('issues_stacked', {
		series: series, 
		displayedValue: opened,
		moreinfo: "<span title=\"#{trend_closed}\">#{closed}</span> closed (#{trend_closed})",
		difference: trend_opened,
		trend_class: trend_class,
		arrow: 'icon-arrow-' + trend_class
	})
end