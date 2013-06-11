#-- copyright
# OpenProject is a project management system.
#
# Copyright (C) 2012-2013 the OpenProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# See doc/COPYRIGHT.rdoc for more details.
#++

FactoryGirl.define do
  factory :time_entry do
    project
    user
    work_unit :factory => :issue
    spent_on Date.today
    activity :factory => :time_entry_activity
    hours 1.0
  end
end

