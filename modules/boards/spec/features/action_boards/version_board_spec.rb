#-- copyright
# OpenProject is a project management system.
# Copyright (C) 2012-2018 the OpenProject Foundation (OPF)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2017 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See docs/COPYRIGHT.rdoc for more details.
#++

require 'spec_helper'
require_relative './../support//board_index_page'
require_relative './../support/board_page'

describe 'Version action board', type: :feature, js: true do
  let(:user) do
    FactoryBot.create(:user,
                      member_in_projects: [project, second_project],
                      member_through_role: role)
  end
  let(:type) { FactoryBot.create(:type_standard) }
  let!(:priority) { FactoryBot.create :default_priority }
  let!(:status) { FactoryBot.create :default_status }
  let(:role) { FactoryBot.create(:role, permissions: permissions) }

  let(:project) { FactoryBot.create(:project, types: [type], enabled_module_names: %i[work_package_tracking board_view]) }
  let(:second_project) { FactoryBot.create(:project) }

  let(:board_index) { Pages::BoardIndex.new(project) }
  let(:permissions) {
    %i[show_board_views manage_board_views add_work_packages
       edit_work_packages view_work_packages manage_public_queries]
  }

  let!(:open_version) { FactoryBot.create :version, project: project, name: 'Open version' }
  let!(:other_version) { FactoryBot.create :version, project: project, name: 'A second version' }
  let!(:different_project_version_) { FactoryBot.create :version, project: second_project, name: 'Version of another project' }
  let!(:shared_version) { FactoryBot.create :version, project: second_project, name: 'Shared version', sharing: 'system' }
  let!(:closed_version) { FactoryBot.create :version, project: project, status: 'closed', name: 'Closed version' }

  let!(:work_package) { FactoryBot.create :work_package, project: project, subject: 'Foo', fixed_version: open_version }
  let(:filters) { ::Components::WorkPackages::Filters.new }

  before do
    with_enterprise_token :board_view
    project
    login_as(user)
  end

  context 'with full boards permissions' do
    it 'allows management of boards' do
      board_index.visit!

      # Create new board
      board_page = board_index.create_board action: :Version

      # expect lists of open versions
      board_page.expect_list 'Open version'
      board_page.expect_list 'A second version'
      board_page.expect_no_list 'Shared version'
      board_page.expect_no_list 'Closed version'
      board_page.expect_no_list 'Version of another project'

      board_page.expect_card 'Open version', work_package.subject, present: true


      board_page.expect_list_option 'Shared version'
      board_page.expect_list_option 'Closed version', present: false

      board_page.board(reload: true) do |board|
        expect(board.name).to eq 'Action board (version)'
        queries = board.contained_queries
        expect(queries.count).to eq(2)

        open = queries.first
        second_open = queries.last

        expect(open.name).to eq 'Open version'
        expect(second_open.name).to eq 'A second version'

        expect(open.filters.first.name).to eq :fixed_version_id
        expect(open.filters.first.values).to eq [open_version.id.to_s]

        expect(second_open.filters.first.name).to eq :fixed_version_id
        expect(second_open.filters.first.values).to eq [other_version.id.to_s]
      end

      # Add item
      board_page.add_list nil, value: 'Shared version'
      board_page.add_card 'Open version', 'Task 1'
      sleep 2

      # Expect added to query
      queries = board_page.board(reload: true).contained_queries
      expect(queries.count).to eq 3
      first = queries.find_by(name: 'Open version')
      second = queries.find_by(name: 'A second version')
      expect(first.ordered_work_packages.count).to eq(2)
      expect(second.ordered_work_packages).to be_empty

      # Expect work package to be saved in query first
      subjects = WorkPackage.where(id: first.ordered_work_packages).pluck(:subject, :fixed_version_id)
      expect(subjects).to match_array [[work_package.subject, open_version.id],['Task 1', open_version.id]]

      # Move item to Closed
      board_page.move_card(0, from: 'Open version', to: 'A second version')
      board_page.expect_card('Open version', 'Task 1', present: false)
      board_page.expect_card('A second version', 'Task 1', present: true)

      # Expect work package to be saved in query second
      sleep 2
      retry_block do
        expect(first.reload.ordered_work_packages.count).to eq(1)
        expect(second.reload.ordered_work_packages.count).to eq(1)
      end

      subjects = WorkPackage.where(id: second.ordered_work_packages).pluck(:subject, :fixed_version_id)
      expect(subjects).to match_array [['Task 1', other_version.id]]

      # Expect that version is not available for global filter selection
      filters.expect_available_filter 'Version', present: false

      # Add filter
      # Filter for Task
      filters.expect_filter_count 0
      filters.open

      filters.quick_filter 'Task'
      board_page.expect_changed
      sleep 2

      board_page.expect_card('Open version', 'Foo', present: false)
      board_page.expect_card('A second version', 'Task 1', present: true)

      # Expect query props to be present
      url = URI.parse(page.current_url).query
      expect(url).to include("query_props=")

      # Save that filter
      board_page.save

      # Expect filter to be saved in board
      board_page.board(reload: true) do |board|
        expect(board.options['filters']).to eq [{ 'search' => { 'operator' => '**', 'values' => ['Task'] } }]
      end

      # Revisit board
      board_page.visit!

      # Expect filter to be present
      filters.expect_filter_count 1
      filters.open
      filters.expect_quick_filter 'Task'

      # No query props visible
      board_page.expect_not_changed

      # Remove query
      board_page.remove_list 'Shared version'
      queries = board_page.board(reload: true).contained_queries
      expect(queries.count).to eq(2)
      expect(queries.first.name).to eq 'Open version'

      board_page.expect_card('Open version', 'Foo', present: false)
      board_page.expect_card('A second version', 'Task 1', present: true)

      subjects = WorkPackage.where(id: second.ordered_work_packages).pluck(:subject, :fixed_version_id)
      expect(subjects).to match_array [['Task 1', other_version.id]]
    end
  end
end
