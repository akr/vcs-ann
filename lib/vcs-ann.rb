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
require 'vcs-ann/main'
