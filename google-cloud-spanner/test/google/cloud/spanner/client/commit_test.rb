# Copyright 2017 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require "helper"

describe Google::Cloud::Spanner::Client, :read, :mock_spanner do
  let(:instance_id) { "my-instance-id" }
  let(:database_id) { "my-database-id" }
  let(:session_id) { "session123" }
  let(:session_grpc) { Google::Spanner::V1::Session.new name: session_path(instance_id, database_id, session_id) }
  let(:commit_time) { Time.now }
  let(:commit_timestamp) { Google::Cloud::Spanner::Convert.time_to_timestamp commit_time }
  let(:commit_resp) { Google::Spanner::V1::CommitResponse.new commit_timestamp: commit_timestamp }
  let(:tx_opts) { Google::Spanner::V1::TransactionOptions.new(read_write: Google::Spanner::V1::TransactionOptions::ReadWrite.new) }
  let(:default_options) { Google::Gax::CallOptions.new kwargs: { "google-cloud-resource-prefix" => database_path(instance_id, database_id) } }
  let(:client) { spanner.client instance_id, database_id, pool: { min: 0 } }

  after do
    # Close the client and release the keepalive thread
    client.instance_variable_get(:@pool).all_sessions = []
    client.close
  end

  def wait_until_thread_pool_is_done!
    pool = client.instance_variable_get :@pool
    thread_pool = pool.instance_variable_get :@thread_pool
    thread_pool.shutdown
    thread_pool.wait_for_termination 60
  end

  it "commits using a block" do
    mutations = [
      Google::Spanner::V1::Mutation.new(
        update: Google::Spanner::V1::Mutation::Write.new(
          table: "users", columns: %w(id name active),
          values: [Google::Cloud::Spanner::Convert.raw_to_value([1, "Charlie", false]).list_value]
        )
      ),
      Google::Spanner::V1::Mutation.new(
        insert: Google::Spanner::V1::Mutation::Write.new(
          table: "users", columns: %w(id name active),
          values: [Google::Cloud::Spanner::Convert.raw_to_value([2, "Harvey", true]).list_value]
        )
      ),
      Google::Spanner::V1::Mutation.new(
        insert_or_update: Google::Spanner::V1::Mutation::Write.new(
          table: "users", columns: %w(id name active),
          values: [Google::Cloud::Spanner::Convert.raw_to_value([3, "Marley", false]).list_value]
        )
      ),
      Google::Spanner::V1::Mutation.new(
        replace: Google::Spanner::V1::Mutation::Write.new(
          table: "users", columns: %w(id name active),
          values: [Google::Cloud::Spanner::Convert.raw_to_value([4, "Henry", true]).list_value]
        )
      ),
      Google::Spanner::V1::Mutation.new(
        delete: Google::Spanner::V1::Mutation::Delete.new(
          table: "users", key_set: Google::Spanner::V1::KeySet.new(
            keys: [1, 2, 3, 4, 5].map do |i|
              Google::Cloud::Spanner::Convert.raw_to_value([i]).list_value
            end
          )
        )
      )
    ]

    mock = Minitest::Mock.new
    mock.expect :create_session, session_grpc, [database_path(instance_id, database_id), options: default_options]
    mock.expect :commit, commit_resp, [session_grpc.name, mutations, transaction_id: nil, single_use_transaction: tx_opts, options: default_options]
    spanner.service.mocked_service = mock

    timestamp = client.commit do |c|
      c.update "users", [{ id: 1, name: "Charlie", active: false }]
      c.insert "users", [{ id: 2, name: "Harvey",  active: true }]
      c.upsert "users", [{ id: 3, name: "Marley",  active: false }]
      c.replace "users", [{ id: 4, name: "Henry",  active: true }]
      c.delete "users", [1, 2, 3, 4, 5]
    end
    timestamp.must_equal commit_time

    wait_until_thread_pool_is_done!

    mock.verify
  end

  it "updates directly" do
    mutations = [
      Google::Spanner::V1::Mutation.new(
        update: Google::Spanner::V1::Mutation::Write.new(
          table: "users", columns: %w(id name active),
          values: [Google::Cloud::Spanner::Convert.raw_to_value([1, "Charlie", false]).list_value]
        )
      )
    ]

    mock = Minitest::Mock.new
    mock.expect :create_session, session_grpc, [database_path(instance_id, database_id), options: default_options]
    mock.expect :commit, commit_resp, [session_grpc.name, mutations, transaction_id: nil, single_use_transaction: tx_opts, options: default_options]
    spanner.service.mocked_service = mock

    timestamp = client.update "users", [{ id: 1, name: "Charlie", active: false }]
    timestamp.must_equal commit_time

    wait_until_thread_pool_is_done!

    mock.verify
  end

  it "inserts directly" do
    mutations = [
      Google::Spanner::V1::Mutation.new(
        insert: Google::Spanner::V1::Mutation::Write.new(
          table: "users", columns: %w(id name active),
          values: [Google::Cloud::Spanner::Convert.raw_to_value([2, "Harvey", true]).list_value]
        )
      )
    ]

    mock = Minitest::Mock.new
    mock.expect :create_session, session_grpc, [database_path(instance_id, database_id), options: default_options]
    mock.expect :commit, commit_resp, [session_grpc.name, mutations, transaction_id: nil, single_use_transaction: tx_opts, options: default_options]
    spanner.service.mocked_service = mock

    timestamp = client.insert "users", [{ id: 2, name: "Harvey",  active: true }]
    timestamp.must_equal commit_time

    wait_until_thread_pool_is_done!

    mock.verify
  end

  it "upserts directly" do
    mutations = [
      Google::Spanner::V1::Mutation.new(
        insert_or_update: Google::Spanner::V1::Mutation::Write.new(
          table: "users", columns: %w(id name active),
          values: [Google::Cloud::Spanner::Convert.raw_to_value([3, "Marley", false]).list_value]
        )
      )
    ]

    mock = Minitest::Mock.new
    mock.expect :create_session, session_grpc, [database_path(instance_id, database_id), options: default_options]
    mock.expect :commit, commit_resp, [session_grpc.name, mutations, transaction_id: nil, single_use_transaction: tx_opts, options: default_options]
    spanner.service.mocked_service = mock

    timestamp = client.upsert "users", [{ id: 3, name: "Marley",  active: false }]
    timestamp.must_equal commit_time

    wait_until_thread_pool_is_done!

    mock.verify
  end

  it "upserts using save alias" do
    mutations = [
      Google::Spanner::V1::Mutation.new(
        insert_or_update: Google::Spanner::V1::Mutation::Write.new(
          table: "users", columns: %w(id name active),
          values: [Google::Cloud::Spanner::Convert.raw_to_value([3, "Marley", false]).list_value]
        )
      )
    ]

    mock = Minitest::Mock.new
    mock.expect :create_session, session_grpc, [database_path(instance_id, database_id), options: default_options]
    mock.expect :commit, commit_resp, [session_grpc.name, mutations, transaction_id: nil, single_use_transaction: tx_opts, options: default_options]
    spanner.service.mocked_service = mock

    timestamp = client.save "users", [{ id: 3, name: "Marley",  active: false }]
    timestamp.must_equal commit_time

    wait_until_thread_pool_is_done!

    mock.verify
  end

  it "replaces directly" do
    mutations = [
      Google::Spanner::V1::Mutation.new(
        replace: Google::Spanner::V1::Mutation::Write.new(
          table: "users", columns: %w(id name active),
          values: [Google::Cloud::Spanner::Convert.raw_to_value([4, "Henry", true]).list_value]
        )
      )
    ]

    mock = Minitest::Mock.new
    mock.expect :create_session, session_grpc, [database_path(instance_id, database_id), options: default_options]
    mock.expect :commit, commit_resp, [session_grpc.name, mutations, transaction_id: nil, single_use_transaction: tx_opts, options: default_options]
    spanner.service.mocked_service = mock

    timestamp = client.replace "users", [{ id: 4, name: "Henry",  active: true }]
    timestamp.must_equal commit_time

    wait_until_thread_pool_is_done!

    mock.verify
  end

  it "deletes multiple rows of keys directly" do
    mutations = [
      Google::Spanner::V1::Mutation.new(
        delete: Google::Spanner::V1::Mutation::Delete.new(
          table: "users", key_set: Google::Spanner::V1::KeySet.new(
            keys: [1, 2, 3, 4, 5].map do |i|
              Google::Cloud::Spanner::Convert.raw_to_value([i]).list_value
            end
          )
        )
      )
    ]

    mock = Minitest::Mock.new
    mock.expect :create_session, session_grpc, [database_path(instance_id, database_id), options: default_options]
    mock.expect :commit, commit_resp, [session_grpc.name, mutations, transaction_id: nil, single_use_transaction: tx_opts, options: default_options]
    spanner.service.mocked_service = mock

    timestamp = client.delete "users", [1, 2, 3, 4, 5]
    timestamp.must_equal commit_time

    wait_until_thread_pool_is_done!

    mock.verify
  end

  it "deletes multiple rows of key rangess directly" do
    mutations = [
      Google::Spanner::V1::Mutation.new(
        delete: Google::Spanner::V1::Mutation::Delete.new(
          table: "users", key_set: Google::Spanner::V1::KeySet.new(
            ranges: [Google::Cloud::Spanner::Convert.to_key_range(1..100)]
          )
        )
      )
    ]

    mock = Minitest::Mock.new
    mock.expect :create_session, session_grpc, [database_path(instance_id, database_id), options: default_options]
    mock.expect :commit, commit_resp, [session_grpc.name, mutations, transaction_id: nil, single_use_transaction: tx_opts, options: default_options]
    spanner.service.mocked_service = mock

    timestamp = client.delete "users", 1..100
    timestamp.must_equal commit_time

    wait_until_thread_pool_is_done!

    mock.verify
  end

  it "deletes a single rows directly" do
    mutations = [
      Google::Spanner::V1::Mutation.new(
        delete: Google::Spanner::V1::Mutation::Delete.new(
          table: "users", key_set: Google::Spanner::V1::KeySet.new(
            keys: [5].map do |i|
              Google::Cloud::Spanner::Convert.raw_to_value([i]).list_value
            end
          )
        )
      )
    ]

    mock = Minitest::Mock.new
    mock.expect :create_session, session_grpc, [database_path(instance_id, database_id), options: default_options]
    mock.expect :commit, commit_resp, [session_grpc.name, mutations, transaction_id: nil, single_use_transaction: tx_opts, options: default_options]
    spanner.service.mocked_service = mock

    timestamp = client.delete "users", 5
    timestamp.must_equal commit_time

    wait_until_thread_pool_is_done!

    mock.verify
  end

  it "deletes all rows directly" do
    mutations = [
      Google::Spanner::V1::Mutation.new(
        delete: Google::Spanner::V1::Mutation::Delete.new(
          table: "users", key_set: Google::Spanner::V1::KeySet.new(all: true)
        )
      )
    ]

    mock = Minitest::Mock.new
    mock.expect :create_session, session_grpc, [database_path(instance_id, database_id), options: default_options]
    mock.expect :commit, commit_resp, [session_grpc.name, mutations, transaction_id: nil, single_use_transaction: tx_opts, options: default_options]
    spanner.service.mocked_service = mock

    timestamp = client.delete "users"
    timestamp.must_equal commit_time

    wait_until_thread_pool_is_done!

    mock.verify
  end
end
