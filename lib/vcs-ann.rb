#!/usr/bin/env ruby

require 'webrick'
require 'pathname'
require 'cgi'
require 'tempfile'
require 'erb'
require 'pp'
require 'open3'

require 'vcs-ann/svn'
require 'vcs-ann/git'

include ERB::Util

class String
  # expand TABs destructively.
  # TAB width is assumed as 8.
  def expand_tab!
    self.sub!(/\A\t+/) { ' ' * ($&.length * 8) }
    nil
  end

  # returns a string which TABs are expanded.
  # TAB width is assumed as 8.
  def expand_tab
    result = dup
    result.expand_tab!
    result
  end
end

def scan_udiff(string)
  ln_cur1 = 0
  ln_cur2 = 0
  ln_num1 = 0
  ln_num2 = 0
  string.each_line {|line|
    line.force_encoding('UTF-8').scrub!
    case line
    when /\A---\s+(\S+)/
      yield :filename1, line, $1
    when /\A\+\+\+\s+(\S+)/
      yield :filename2, line, $1
    when /\A@@ -(\d+),(\d+) \+(\d+),(\d+) @@/
      ln_cur1 = $1.to_i
      ln_num1 = $2.to_i
      ln_cur2 = $3.to_i
      ln_num2 = $4.to_i
      yield :hunk_header, line, ln_cur1, ln_num1, ln_cur2, ln_num2
    else
      if /\A-/ =~ line && 0 < ln_num1
        content_line = $'
        yield :del, line, content_line, ln_cur1
        ln_cur1 += 1
        ln_num1 -= 1
      elsif /\A\+/ =~ line && 0 < ln_num2
        content_line = $'
        yield :add, line, content_line, ln_cur2
        ln_cur2 += 1
        ln_num2 -= 1
      elsif /\A / =~ line && 0 < ln_num1 && 0 < ln_num2
        content_line = $'
        yield :com, line, content_line, ln_cur1, ln_cur2
        ln_cur1 += 1
        ln_cur2 += 1
        ln_num1 -= 1
        ln_num2 -= 1
      else
        yield :other, line
      end
    end
  }
end

NullLogSink = Object.new
def NullLogSink.<<(s)
end
NullLog = WEBrick::BasicLog.new(NullLogSink)

class Server
  def initialize(repo)
    @repo = repo
    @httpd = WEBrick::HTTPServer.new(
     :BindAddress => '127.0.0.1',
     :Port => 0,
     :AccessLog => NullLog,
     :Logger => NullLog)
    @httpd.mount_proc("/") {|req, res|
      handle_request0(repo, req, res)
    }
    trap(:INT){ @httpd.shutdown }
    addr = @httpd.listeners[0].connect_address
    @http_root = "http://#{addr.ip_address}:#{addr.ip_port}"
    @th = Thread.new { @httpd.start }
  end

  def stop
    @httpd.shutdown
    @th.join
  end

  def annotate_url(relpath, rev)
    reluri = relpath.gsub(%r{[^/]+}) { CGI.escape($&) }
    reluri = '/' + reluri if %r{\A/} !~ reluri
    "#{@http_root}/file/#{rev}#{reluri}"
  end

  def handle_request0(repo, req, res)
    begin
      handle_request(repo, req, res)
    rescue Exception
      res.content_type = 'text/html'
      result = '<pre>'
      result << "#{h $!.message} (#{h $!.class})\n"
      $!.backtrace.each {|b|
        result << "#{h b}\n"
      }
      result << "</pre>"
      res.body = result
    end
  end

  def handle_request(repo, req, res)
    res.content_type = 'text/html'
    list = req.request_uri.path.scan(%r{[^/]+}).map {|s| CGI.unescape(s) }
    case list[0]
    when 'file'
      res.body = repo.format_file list[1..-1]
    when 'commit'
      res.body = repo.format_commit list[1..-1]
    else
      raise "unexpected command"
    end
  end
end

def find_svn_repository(arg)
  svn_info_xml = IO.popen(['svn', 'info', '--xml', arg]) {|io| io.read }

  # <url>http://svn.ruby-lang.org/repos/ruby/trunk/ChangeLog</url>
  # <root>http://svn.ruby-lang.org/repos/ruby</root>
  # <commit
  #    revision="44930">

  if %r{<url>(.*?)</url>} !~ svn_info_xml
    raise "unexpected 'svn info' result: no url element"
  end
  url = CGI.unescapeHTML($1)
  if %r{<root>(.*?)</root>} !~ svn_info_xml
    raise "unexpected 'svn info' result: no root element"
  end
  root = CGI.unescapeHTML($1)
  if %r{#{Regexp.escape root}} !~ url
    raise "unexpected 'svn info' result: url is not a prefix of root"
  end
  relpath = $'
  if !relpath.empty? && %r{\A/} !~ relpath
    raise "unexpected 'svn info' result: relpath doesn't start with a slash"
  end

  if %r{<commit\s+revision="(\d+)">} !~ svn_info_xml
    raise "unexpected 'svn info' result: no revision"
  end
  rev = $1.to_i

  return SVNRepo.new(root), relpath, rev
end

def find_git_repository(realpath, d)
  relpath = realpath.relative_path_from(d).to_s
  rev, status = Open3.capture2('git', '-C', d.to_s, 'log', '--pretty=format:%H', '-1', relpath.to_s)
  if !status.success?
    raise "git log failed"
  end
  return GITRepo.new(d), relpath, rev
end

def parse_arguments(argv)
  # process options
  filename = argv[0]
  filename
end

def setup_repository(filename)
  realpath = Pathname(filename).realpath
  realpath.dirname.ascend {|d|
    if (d+".svn").exist?
      return find_svn_repository(filename)
    end
    if (d+".git").exist?
      return find_git_repository(realpath, d)
    end
  }
  raise "cannot find a repository"
end

def run_browser(url)
  system "w3m", url
end

def main(argv)
  filename = parse_arguments(argv)
  repo, relpath, rev = setup_repository filename
  server = Server.new(repo)
  run_browser server.annotate_url(relpath, rev)
  server.stop
end
