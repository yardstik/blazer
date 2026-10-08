require_relative "test_helper"

class PermissionsTest < ActionDispatch::IntegrationTest
  def setup
    Blazer::Query.delete_all
    User.delete_all
  end

  def test_list
    with_new_user do |user|
      create_query(name: "# Test", creator: user)
      get blazer.root_path
      assert_response :success
      assert_match "# Test", response.body
    end

    with_new_user do
      get blazer.root_path
      assert_response :success
      refute_match "# Test", response.body
    end
  end

  def test_edit
    query =
      with_new_user do |user|
        create_query(name: "* Test", creator: user)
      end

    with_new_user do
      patch blazer.query_path(query), params: {query: {name: "Renamed"}}
      assert_response :unprocessable_entity
      assert_match "Sorry, permission denied", response.body

      delete blazer.query_path(query)
      # TODO error response
      assert_response :redirect
      assert Blazer::Query.exists?(query.id)
    end
  end

  def test_change_creator
    with_new_user do |user|
      query = create_query(name: "Test", creator: user)

      patch blazer.query_path(query), params: {query: {name: "* Test"}}
      assert_response :redirect

      patch blazer.query_path(query), params: {query: {name: "# Test"}}
      assert_response :redirect
    end
  end

  def test_edit_query_hook_denied
    query = create_query(name: "Test", creator: User.create!)

    with_user_hook(:can_edit_blazer_query?, false) do
      patch blazer.query_path(query), params: {query: {name: "Renamed"}}
      assert_response :unprocessable_entity
      assert_match "Sorry, permission denied", response.body

      delete blazer.query_path(query)
      assert Blazer::Query.exists?(query.id)
    end
  end

  def test_edit_query_hook_allowed
    query = create_query(name: "* Test", creator: User.create!)

    with_user_hook(:can_edit_blazer_query?, true) do
      patch blazer.query_path(query), params: {query: {name: "Renamed"}}
      assert_response :redirect
      assert_equal "Renamed", query.reload.name
    end
  end

  def test_edit_query_hook_allows_fork
    query = create_query(name: "Test", creator: User.create!)

    with_user_hook(:can_edit_blazer_query?, false) do
      patch blazer.query_path(query), params: {commit: "Fork", query: {name: "Forked", statement: "SELECT 1", data_source: "main"}}
      assert_response :redirect
      assert Blazer::Query.exists?(name: "Forked")
    end
  end

  def test_edit_dashboard_hook_denied
    Blazer::Dashboard.delete_all
    dashboard = Blazer::Dashboard.create!(name: "Test")

    with_user_hook(:can_edit_blazer_dashboard?, false) do
      get blazer.dashboard_path(dashboard)
      assert_response :success
      refute_match "Edit", response.body

      get blazer.edit_dashboard_path(dashboard)
      assert_response :forbidden

      patch blazer.dashboard_path(dashboard), params: {dashboard: {name: "Renamed"}}
      assert_response :forbidden

      delete blazer.dashboard_path(dashboard)
      assert_response :forbidden
      assert Blazer::Dashboard.exists?(dashboard.id)
    end
  end

  def test_edit_dashboard_hook_allowed
    Blazer::Dashboard.delete_all
    dashboard = Blazer::Dashboard.create!(name: "Test")

    with_user_hook(:can_edit_blazer_dashboard?, true) do
      get blazer.edit_dashboard_path(dashboard)
      assert_response :success
    end
  end

  def test_edit_check_hook_denied
    Blazer::Check.delete_all
    check = create_check(query: create_query, emails: "hi@example.org")

    with_user_hook(:can_edit_blazer_check?, false) do
      get blazer.checks_path
      assert_response :success
      refute_match blazer.edit_check_path(check), response.body

      get blazer.edit_check_path(check)
      assert_response :forbidden

      delete blazer.check_path(check)
      assert_response :forbidden
      assert Blazer::Check.exists?(check.id)
    end
  end

  def test_edit_check_hook_allowed
    Blazer::Check.delete_all
    check = create_check(query: create_query, emails: "hi@example.org")

    with_user_hook(:can_edit_blazer_check?, true) do
      get blazer.edit_check_path(check)
      assert_response :success
    end
  end

  private

  def with_user_hook(name, value)
    User.define_method(name) { |_resource| value }
    User.create!
    yield
  ensure
    User.remove_method(name)
  end

  def with_new_user
    user = User.create!
    yield user
  end
end
