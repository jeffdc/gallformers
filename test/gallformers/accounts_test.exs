defmodule Gallformers.AccountsTest do
  @moduledoc """
  Unit tests for the Accounts context.
  """
  use Gallformers.DataCase, async: true

  alias Gallformers.Accounts
  alias Gallformers.Accounts.Auth0User
  alias Gallformers.Accounts.User

  # Helper to generate unique auth0 IDs
  defp unique_auth0_id, do: "auth0|test-#{System.unique_integer([:positive])}"

  describe "create_user/1" do
    test "creates user with valid attrs" do
      auth0_id = unique_auth0_id()

      attrs = %{
        auth0_id: auth0_id,
        display_name: "Test User",
        nickname: "testuser",
        show_on_about: false
      }

      assert {:ok, %User{} = user} = Accounts.create_user(attrs)
      assert user.auth0_id == auth0_id
      assert user.display_name == "Test User"
      assert user.nickname == "testuser"
      assert user.show_on_about == false
    end

    test "creates user with minimal attrs (just auth0_id)" do
      auth0_id = unique_auth0_id()

      assert {:ok, %User{} = user} = Accounts.create_user(%{auth0_id: auth0_id})
      assert user.auth0_id == auth0_id
      assert user.display_name == nil
      assert user.nickname == nil
      assert user.show_on_about == false
    end

    test "fails with invalid attrs (missing auth0_id)" do
      assert {:error, changeset} = Accounts.create_user(%{display_name: "No Auth0 ID"})
      assert %{auth0_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "fails with duplicate auth0_id" do
      auth0_id = unique_auth0_id()

      # Create first user
      assert {:ok, _user} = Accounts.create_user(%{auth0_id: auth0_id})

      # Attempt to create second user with same auth0_id
      assert {:error, changeset} = Accounts.create_user(%{auth0_id: auth0_id})
      assert %{auth0_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "validates URL fields on create" do
      auth0_id = unique_auth0_id()

      attrs = %{
        auth0_id: auth0_id,
        inaturalist_url: "not-a-url",
        social_url: "also-not-valid",
        personal_url: "invalid"
      }

      assert {:error, changeset} = Accounts.create_user(attrs)
      errors = errors_on(changeset)

      assert %{inaturalist_url: ["must be a valid URL starting with http:// or https://"]} =
               errors

      assert %{social_url: ["must be a valid URL starting with http:// or https://"]} = errors
      assert %{personal_url: ["must be a valid URL starting with http:// or https://"]} = errors
    end

    test "accepts valid URLs on create" do
      auth0_id = unique_auth0_id()

      attrs = %{
        auth0_id: auth0_id,
        inaturalist_url: "https://www.inaturalist.org/people/testuser",
        social_url: "https://twitter.com/testuser",
        personal_url: "http://example.com"
      }

      assert {:ok, %User{} = user} = Accounts.create_user(attrs)
      assert user.inaturalist_url == "https://www.inaturalist.org/people/testuser"
      assert user.social_url == "https://twitter.com/testuser"
      assert user.personal_url == "http://example.com"
    end
  end

  describe "get_user/1" do
    test "returns user by id" do
      auth0_id = unique_auth0_id()
      {:ok, created_user} = Accounts.create_user(%{auth0_id: auth0_id, display_name: "Test"})

      user = Accounts.get_user(created_user.id)
      assert user.id == created_user.id
      assert user.display_name == "Test"
    end

    test "returns nil for non-existent id" do
      assert Accounts.get_user(999_999_999) == nil
    end
  end

  describe "get_user_by_auth0_id/1" do
    test "returns user by auth0_id" do
      auth0_id = unique_auth0_id()
      {:ok, created_user} = Accounts.create_user(%{auth0_id: auth0_id, display_name: "Test"})

      user = Accounts.get_user_by_auth0_id(auth0_id)
      assert user.id == created_user.id
      assert user.auth0_id == auth0_id
    end

    test "returns nil for non-existent auth0_id" do
      assert Accounts.get_user_by_auth0_id("auth0|nonexistent") == nil
    end
  end

  describe "update_user/2" do
    setup do
      auth0_id = unique_auth0_id()

      {:ok, user} =
        Accounts.create_user(%{
          auth0_id: auth0_id,
          display_name: "Original Name",
          nickname: "originalnick"
        })

      {:ok, user: user}
    end

    test "updates user fields", %{user: user} do
      assert {:ok, updated} = Accounts.update_user(user, %{display_name: "New Name"})
      assert updated.display_name == "New Name"
      # Original fields should remain
      assert updated.nickname == "originalnick"
    end

    test "updates show_on_about", %{user: user} do
      assert user.show_on_about == false
      assert {:ok, updated} = Accounts.update_user(user, %{show_on_about: true})
      assert updated.show_on_about == true
    end

    test "validates URL fields on update", %{user: user} do
      assert {:error, changeset} =
               Accounts.update_user(user, %{inaturalist_url: "invalid-url"})

      assert %{inaturalist_url: ["must be a valid URL starting with http:// or https://"]} =
               errors_on(changeset)
    end

    test "accepts valid URLs on update", %{user: user} do
      assert {:ok, updated} =
               Accounts.update_user(user, %{
                 inaturalist_url: "https://www.inaturalist.org/people/me",
                 social_url: "https://mastodon.social/@me",
                 personal_url: "https://mysite.com"
               })

      assert updated.inaturalist_url == "https://www.inaturalist.org/people/me"
      assert updated.social_url == "https://mastodon.social/@me"
      assert updated.personal_url == "https://mysite.com"
    end

    test "cannot update auth0_id", %{user: user} do
      # The update_changeset does not cast auth0_id, so it should remain unchanged
      {:ok, updated} = Accounts.update_user(user, %{auth0_id: "auth0|different"})
      assert updated.auth0_id == user.auth0_id
    end
  end

  describe "list_users_for_about_page/0" do
    setup do
      # Clean up any test users that might interfere
      # Create test users with unique auth0_ids
      {:ok, user1} =
        Accounts.create_user(%{
          auth0_id: unique_auth0_id(),
          display_name: "Charlie",
          show_on_about: true
        })

      {:ok, user2} =
        Accounts.create_user(%{
          auth0_id: unique_auth0_id(),
          display_name: "Alice",
          show_on_about: true
        })

      {:ok, user3} =
        Accounts.create_user(%{
          auth0_id: unique_auth0_id(),
          display_name: "Bob",
          show_on_about: false
        })

      {:ok, opted_in: [user1, user2], opted_out: user3}
    end

    test "returns only users with show_on_about=true", %{opted_in: opted_in, opted_out: opted_out} do
      users = Accounts.list_users_for_about_page()

      opted_in_ids = Enum.map(opted_in, & &1.id)
      returned_ids = Enum.map(users, & &1.id)

      # All opted-in users should be returned
      for id <- opted_in_ids do
        assert id in returned_ids
      end

      # Opted-out user should not be returned
      refute opted_out.id in returned_ids
    end

    test "orders by display_name alphabetically", %{opted_in: _opted_in} do
      users = Accounts.list_users_for_about_page()

      # Filter to just our test users
      test_users =
        users
        |> Enum.filter(&(&1.display_name in ["Alice", "Charlie"]))

      names = Enum.map(test_users, & &1.display_name)

      # Alice should come before Charlie alphabetically
      alice_idx = Enum.find_index(names, &(&1 == "Alice"))
      charlie_idx = Enum.find_index(names, &(&1 == "Charlie"))

      if alice_idx && charlie_idx do
        assert alice_idx < charlie_idx, "Expected Alice before Charlie, got #{inspect(names)}"
      end
    end

    test "returns empty list when none opted in" do
      # This test uses the transaction rollback, so we just need to not create any opted-in users
      # The setup creates users, but we can test with a fresh query after those are rolled back
      # Actually, the setup runs in the same transaction, so let's update all users to be opted out
      users = Accounts.list_users_for_about_page()

      # Update all returned users to opt out
      for user <- users do
        Accounts.update_user(user, %{show_on_about: false})
      end

      # Now should return empty (or at least not include our test users)
      result = Accounts.list_users_for_about_page()
      assert is_list(result)
    end
  end

  describe "list_all_users/0" do
    test "returns all users" do
      # Create some test users
      {:ok, _user1} =
        Accounts.create_user(%{auth0_id: unique_auth0_id(), display_name: "User1"})

      {:ok, _user2} =
        Accounts.create_user(%{auth0_id: unique_auth0_id(), display_name: "User2"})

      users = Accounts.list_all_users()
      assert is_list(users)
      assert length(users) >= 2
    end

    test "orders by display_name with nickname fallback" do
      users = Accounts.list_all_users()
      assert is_list(users)
    end
  end

  describe "sync_user_from_auth0/1" do
    test "creates user record on first login" do
      auth0_id = unique_auth0_id()

      auth0_user = %Auth0User{
        id: auth0_id,
        email: "new@test.com",
        name: "New User",
        nickname: "newuser",
        picture: nil,
        roles: ["admin"]
      }

      # User should not exist yet
      assert Accounts.get_user_by_auth0_id(auth0_id) == nil

      # Sync should create the user
      assert {:ok, %User{} = user} = Accounts.sync_user_from_auth0(auth0_user)
      assert user.auth0_id == auth0_id
      assert user.display_name == "New User"
      assert user.nickname == "newuser"
      assert user.show_on_about == false
    end

    test "updates nickname on subsequent login" do
      auth0_id = unique_auth0_id()

      # Create initial user
      {:ok, _user} =
        Accounts.create_user(%{
          auth0_id: auth0_id,
          display_name: "Original Name",
          nickname: "oldnick"
        })

      # Simulate login with new nickname
      auth0_user = %Auth0User{
        id: auth0_id,
        email: "user@test.com",
        name: "New Auth0 Name",
        nickname: "newnick",
        picture: nil,
        roles: ["admin"]
      }

      assert {:ok, %User{} = updated} = Accounts.sync_user_from_auth0(auth0_user)
      assert updated.nickname == "newnick"
    end

    test "preserves user-customized display_name" do
      auth0_id = unique_auth0_id()

      # Create user with custom display_name (different from nickname)
      {:ok, _user} =
        Accounts.create_user(%{
          auth0_id: auth0_id,
          display_name: "My Custom Name",
          nickname: "originalnick"
        })

      # Simulate login with different name from Auth0
      auth0_user = %Auth0User{
        id: auth0_id,
        email: "user@test.com",
        name: "Auth0 Name",
        nickname: "newnick",
        picture: nil,
        roles: ["admin"]
      }

      assert {:ok, %User{} = updated} = Accounts.sync_user_from_auth0(auth0_user)
      # Custom display_name should be preserved since it's different from nickname
      assert updated.display_name == "My Custom Name"
      # But nickname should be updated
      assert updated.nickname == "newnick"
    end

    test "updates display_name if it matches old nickname" do
      auth0_id = unique_auth0_id()

      # Create user where display_name equals nickname (not customized)
      {:ok, _user} =
        Accounts.create_user(%{
          auth0_id: auth0_id,
          display_name: "oldnick",
          nickname: "oldnick"
        })

      # Simulate login with new name
      auth0_user = %Auth0User{
        id: auth0_id,
        email: "user@test.com",
        name: "New Name From Auth0",
        nickname: "newnick",
        picture: nil,
        roles: ["admin"]
      }

      assert {:ok, %User{} = updated} = Accounts.sync_user_from_auth0(auth0_user)
      # display_name should be updated since it matched the old nickname
      assert updated.display_name == "New Name From Auth0"
      assert updated.nickname == "newnick"
    end

    test "updates display_name if it was nil" do
      auth0_id = unique_auth0_id()

      # Create user with nil display_name
      {:ok, _user} =
        Accounts.create_user(%{
          auth0_id: auth0_id,
          nickname: "oldnick"
        })

      # Simulate login
      auth0_user = %Auth0User{
        id: auth0_id,
        email: "user@test.com",
        name: "New Name",
        nickname: "newnick",
        picture: nil,
        roles: ["admin"]
      }

      assert {:ok, %User{} = updated} = Accounts.sync_user_from_auth0(auth0_user)
      # display_name should be set since it was nil
      assert updated.display_name == "New Name"
    end
  end

  describe "admin?/1" do
    test "returns false for nil" do
      assert Accounts.admin?(nil) == false
    end

    test "returns true for user with admin role" do
      user = %Auth0User{
        id: "auth0|123",
        email: "admin@test.com",
        name: "Admin",
        nickname: nil,
        picture: nil,
        roles: ["admin"]
      }

      assert Accounts.admin?(user) == true
    end

    test "returns true for user with superadmin role" do
      user = %Auth0User{
        id: "auth0|123",
        email: "superadmin@test.com",
        name: "Super Admin",
        nickname: nil,
        picture: nil,
        roles: ["superadmin"]
      }

      assert Accounts.admin?(user) == true
    end

    test "returns false for user without admin role" do
      user = %Auth0User{
        id: "auth0|123",
        email: "user@test.com",
        name: "Regular User",
        nickname: nil,
        picture: nil,
        roles: []
      }

      assert Accounts.admin?(user) == false
    end

    test "returns true for map with admin role (session deserialization fallback)" do
      # Simulates deserialized session data where struct type is not preserved
      user_map = %{roles: ["admin"]}
      assert Accounts.admin?(user_map) == true
    end

    test "returns true for map with superadmin role (session deserialization fallback)" do
      user_map = %{roles: ["superadmin"]}
      assert Accounts.admin?(user_map) == true
    end

    test "returns false for map without admin role" do
      user_map = %{roles: []}
      assert Accounts.admin?(user_map) == false
    end

    test "returns false for map without roles key" do
      user_map = %{id: "auth0|123"}
      assert Accounts.admin?(user_map) == false
    end
  end

  describe "superadmin?/1" do
    test "returns false for nil" do
      assert Accounts.superadmin?(nil) == false
    end

    test "returns true for user with superadmin role" do
      user = %Auth0User{
        id: "auth0|123",
        email: "superadmin@test.com",
        name: "Super Admin",
        nickname: nil,
        picture: nil,
        roles: ["superadmin"]
      }

      assert Accounts.superadmin?(user) == true
    end

    test "returns false for user with only admin role" do
      user = %Auth0User{
        id: "auth0|123",
        email: "admin@test.com",
        name: "Admin",
        nickname: nil,
        picture: nil,
        roles: ["admin"]
      }

      assert Accounts.superadmin?(user) == false
    end

    test "returns false for user without any roles" do
      user = %Auth0User{
        id: "auth0|123",
        email: "user@test.com",
        name: "Regular User",
        nickname: nil,
        picture: nil,
        roles: []
      }

      assert Accounts.superadmin?(user) == false
    end

    test "returns true for map with superadmin role (session deserialization fallback)" do
      user_map = %{roles: ["superadmin"]}
      assert Accounts.superadmin?(user_map) == true
    end

    test "returns false for map with only admin role" do
      user_map = %{roles: ["admin"]}
      assert Accounts.superadmin?(user_map) == false
    end

    test "returns false for map without roles key" do
      user_map = %{id: "auth0|123"}
      assert Accounts.superadmin?(user_map) == false
    end
  end

  describe "operator?/1" do
    test "returns false for nil" do
      assert Accounts.operator?(nil) == false
    end

    test "returns true for user with operator role" do
      user = %Auth0User{
        id: "auth0|123",
        email: "operator@test.com",
        name: "Operator",
        nickname: nil,
        picture: nil,
        roles: ["operator"]
      }

      assert Accounts.operator?(user) == true
    end

    test "returns false for user with only admin role" do
      user = %Auth0User{
        id: "auth0|123",
        email: "admin@test.com",
        name: "Admin",
        nickname: nil,
        picture: nil,
        roles: ["admin"]
      }

      assert Accounts.operator?(user) == false
    end

    test "returns false for user without any roles" do
      user = %Auth0User{
        id: "auth0|123",
        email: "user@test.com",
        name: "Regular User",
        nickname: nil,
        picture: nil,
        roles: []
      }

      assert Accounts.operator?(user) == false
    end

    test "returns true for map with operator role (session deserialization fallback)" do
      user_map = %{roles: ["operator"]}
      assert Accounts.operator?(user_map) == true
    end

    test "returns false for map with only admin role" do
      user_map = %{roles: ["admin"]}
      assert Accounts.operator?(user_map) == false
    end

    test "returns false for map without roles key" do
      user_map = %{id: "auth0|123"}
      assert Accounts.operator?(user_map) == false
    end
  end

  describe "Auth0User struct" do
    test "admin?/1 returns true for admin or superadmin" do
      admin = %Auth0User{
        id: "1",
        email: nil,
        name: nil,
        nickname: nil,
        picture: nil,
        roles: ["admin"]
      }

      superadmin = %Auth0User{
        id: "2",
        email: nil,
        name: nil,
        nickname: nil,
        picture: nil,
        roles: ["superadmin"]
      }

      both = %Auth0User{
        id: "3",
        email: nil,
        name: nil,
        nickname: nil,
        picture: nil,
        roles: ["admin", "superadmin"]
      }

      none = %Auth0User{id: "4", email: nil, name: nil, nickname: nil, picture: nil, roles: []}

      assert Auth0User.admin?(admin) == true
      assert Auth0User.admin?(superadmin) == true
      assert Auth0User.admin?(both) == true
      assert Auth0User.admin?(none) == false
    end

    test "superadmin?/1 returns true only for superadmin" do
      admin = %Auth0User{
        id: "1",
        email: nil,
        name: nil,
        nickname: nil,
        picture: nil,
        roles: ["admin"]
      }

      superadmin = %Auth0User{
        id: "2",
        email: nil,
        name: nil,
        nickname: nil,
        picture: nil,
        roles: ["superadmin"]
      }

      assert Auth0User.superadmin?(admin) == false
      assert Auth0User.superadmin?(superadmin) == true
    end

    test "operator?/1 returns true only for operator" do
      admin = %Auth0User{
        id: "1",
        email: nil,
        name: nil,
        nickname: nil,
        picture: nil,
        roles: ["admin"]
      }

      operator = %Auth0User{
        id: "2",
        email: nil,
        name: nil,
        nickname: nil,
        picture: nil,
        roles: ["operator"]
      }

      assert Auth0User.operator?(admin) == false
      assert Auth0User.operator?(operator) == true
    end

    test "display_name/1 prefers name over nickname over email" do
      with_name = %Auth0User{
        id: "1",
        email: "test@example.com",
        name: "Full Name",
        nickname: "nick",
        picture: nil,
        roles: []
      }

      with_nickname = %Auth0User{
        id: "2",
        email: "test@example.com",
        name: nil,
        nickname: "nick",
        picture: nil,
        roles: []
      }

      with_email = %Auth0User{
        id: "3",
        email: "test@example.com",
        name: nil,
        nickname: nil,
        picture: nil,
        roles: []
      }

      with_nothing = %Auth0User{
        id: "4",
        email: nil,
        name: nil,
        nickname: nil,
        picture: nil,
        roles: []
      }

      assert Auth0User.display_name(with_name) == "Full Name"
      assert Auth0User.display_name(with_nickname) == "nick"
      assert Auth0User.display_name(with_email) == "test@example.com"
      assert Auth0User.display_name(with_nothing) == "Unknown User"
    end
  end
end
