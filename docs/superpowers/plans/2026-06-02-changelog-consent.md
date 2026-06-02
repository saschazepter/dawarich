# Changelog Consent (Dawarich side) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development for each task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Per-user opt-in for the chibichange "What's New" widget — prompt each user once, record their choice in the DB, show the chibichange green pill if they consent, and keep the existing native GitHub-release "bang" badge if they decline or haven't answered.

**Architecture:** A nullable `changelog_consent` enum column on `users` (`nil` = not yet asked, `declined`, `granted`). The navbar version badge becomes a partial with three states driven by that column. A consent prompt (pure Turbo, two `button_to` forms) posts to a new `SettingsController#changelog_consent` action that flips the column and replaces the indicator via Turbo Stream. Only when `granted` does Dawarich render the chibichange `<script>` tag — declined/unprompted users make **zero** requests to chibichange (the asset is never fetched). This preserves Dawarich's no-phone-home contract for anyone who hasn't explicitly opted in.

**Tech Stack:** Rails 8, Hotwire (Turbo + Stimulus-free), Tailwind + DaisyUI, RSpec + FactoryBot.

---

## File Structure

- `db/migrate/<ts>_add_changelog_consent_to_users.rb` — new nullable integer column.
- `app/models/user.rb` — enum + `changelog_prompt_pending?`.
- `app/controllers/settings_controller.rb` — `changelog_consent` action.
- `config/routes.rb` — `patch 'settings/changelog_consent'`.
- `app/helpers/changelog_helper.rb` — `chibichange_widget_src`, slug/host config.
- `config/initializers/01_constants.rb` — `CHIBICHANGE_WIDGET_HOST`, `CHIBICHANGE_SLUG`.
- `app/views/shared/navbar/_version_indicator.html.erb` — three-state partial (new).
- `app/views/shared/navbar/_changelog_prompt.html.erb` — the polite opt-in card (new).
- `app/views/settings/changelog_consent.turbo_stream.erb` — stream replacing the indicator (new).
- `app/views/shared/_navbar.html.erb:56-66` — replace inline badge with the partial.

---

### Task 1: `changelog_consent` column + User enum

**Files:**
- Create: `db/migrate/<ts>_add_changelog_consent_to_users.rb`
- Modify: `app/models/user.rb`
- Test: `spec/models/user_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/models/user_spec.rb — inside RSpec.describe User
describe 'changelog consent' do
  it 'defaults to nil (not yet prompted) and reports prompt pending' do
    user = create(:user)
    expect(user.changelog_consent).to be_nil
    expect(user.changelog_prompt_pending?).to be(true)
  end

  it 'records a granted choice' do
    user = create(:user)
    user.update!(changelog_consent: :granted)
    expect(user.changelog_consent_granted?).to be(true)
    expect(user.changelog_prompt_pending?).to be(false)
  end

  it 'records a declined choice' do
    user = create(:user)
    user.update!(changelog_consent: :declined)
    expect(user.changelog_consent_declined?).to be(true)
    expect(user.changelog_prompt_pending?).to be(false)
  end
end
```

- [ ] **Step 2: Run it, verify it fails**

Run: `bundle exec rspec spec/models/user_spec.rb -e "changelog consent"`
Expected: FAIL — `NoMethodError: undefined method 'changelog_prompt_pending?'` / unknown attribute.

- [ ] **Step 3: Write the migration**

```ruby
# frozen_string_literal: true

class AddChangelogConsentToUsers < ActiveRecord::Migration[8.0]
  def change
    # Nullable, no default: nil means "user has not been prompted yet".
    add_column :users, :changelog_consent, :integer
  end
end
```

- [ ] **Step 4: Migrate**

Run: `bundle exec rails db:migrate`
Expected: schema.rb gains `t.integer "changelog_consent"` on `users`.

- [ ] **Step 5: Add enum + helper to User**

```ruby
# app/models/user.rb — near the other enums (e.g. plan)
enum :changelog_consent, { declined: 0, granted: 1 }, prefix: :changelog_consent

def changelog_prompt_pending?
  changelog_consent.nil?
end
```

- [ ] **Step 6: Run test, verify pass**

Run: `bundle exec rspec spec/models/user_spec.rb -e "changelog consent"`
Expected: PASS (3 examples).

- [ ] **Step 7: Commit** (only on explicit user instruction — do not auto-commit)

---

### Task 2: Consent controller + route

**Files:**
- Modify: `app/controllers/settings_controller.rb`
- Modify: `config/routes.rb` (after line 84, near other `settings/*` routes)
- Create: `app/views/settings/changelog_consent.turbo_stream.erb`
- Test: `spec/requests/settings_spec.rb` (create if absent)

- [ ] **Step 1: Write the failing request test**

```ruby
# spec/requests/settings_spec.rb
require 'rails_helper'

RSpec.describe 'Settings::ChangelogConsent', type: :request do
  let(:user) { create(:user) }
  before { sign_in user }

  it 'records granted and responds with a turbo stream' do
    patch '/settings/changelog_consent', params: { decision: 'granted' },
          headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
    expect(response).to have_http_status(:ok)
    expect(user.reload.changelog_consent_granted?).to be(true)
    expect(response.body).to include('version-indicator')
  end

  it 'records declined' do
    patch '/settings/changelog_consent', params: { decision: 'declined' },
          headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
    expect(user.reload.changelog_consent_declined?).to be(true)
  end

  it 'rejects an invalid decision without changing state' do
    patch '/settings/changelog_consent', params: { decision: 'bogus' }
    expect(user.reload.changelog_consent).to be_nil
  end
end
```

- [ ] **Step 2: Run it, verify it fails**

Run: `bundle exec rspec spec/requests/settings_spec.rb`
Expected: FAIL — routing error (no such route).

- [ ] **Step 3: Add the route**

```ruby
# config/routes.rb — directly after: get 'settings/theme', ...
patch 'settings/changelog_consent', to: 'settings#changelog_consent', as: :changelog_consent
```

- [ ] **Step 4: Add the controller action**

```ruby
# app/controllers/settings_controller.rb
DECISIONS = %w[granted declined].freeze

def changelog_consent
  decision = params[:decision].to_s
  current_user.update!(changelog_consent: decision) if DECISIONS.include?(decision)

  respond_to do |format|
    format.turbo_stream
    format.html { redirect_back(fallback_location: root_path) }
  end
end
```

- [ ] **Step 5: Add the turbo_stream view**

```erb
<%# app/views/settings/changelog_consent.turbo_stream.erb %>
<%= turbo_stream.replace "version-indicator" do %>
  <%= render "shared/navbar/version_indicator" %>
<% end %>
```

- [ ] **Step 6: Run test, verify pass**

Run: `bundle exec rspec spec/requests/settings_spec.rb`
Expected: PASS (3 examples). (Depends on the partial from Task 3 existing; create a stub partial first if running in isolation, or run Task 3 before Step 6.)

- [ ] **Step 7: Commit** (only on explicit user instruction)

---

### Task 3: Navbar version-indicator partial (3 states) + prompt + widget config

**Files:**
- Modify: `config/initializers/01_constants.rb`
- Create: `app/helpers/changelog_helper.rb`
- Create: `app/views/shared/navbar/_version_indicator.html.erb`
- Create: `app/views/shared/navbar/_changelog_prompt.html.erb`
- Modify: `app/views/shared/_navbar.html.erb:56-66`
- Test: `spec/helpers/changelog_helper_spec.rb`

- [ ] **Step 1: Write the failing helper test**

```ruby
# spec/helpers/changelog_helper_spec.rb
require 'rails_helper'

RSpec.describe ChangelogHelper, type: :helper do
  it 'builds the widget loader src from the configured host' do
    stub_const('CHIBICHANGE_WIDGET_HOST', 'https://my.chibichange.com')
    expect(helper.chibichange_widget_src).to eq('https://my.chibichange.com/w/v1/loader.js')
  end
end
```

- [ ] **Step 2: Run it, verify it fails**

Run: `bundle exec rspec spec/helpers/changelog_helper_spec.rb`
Expected: FAIL — uninitialized constant ChangelogHelper.

- [ ] **Step 3: Add config constants**

```ruby
# config/initializers/01_constants.rb — append near other ENV-driven constants
CHIBICHANGE_WIDGET_HOST = ENV.fetch('CHIBICHANGE_WIDGET_HOST', 'https://my.chibichange.com')
CHIBICHANGE_SLUG        = ENV.fetch('CHIBICHANGE_SLUG', 'dawarich')
```

- [ ] **Step 4: Add the helper**

```ruby
# frozen_string_literal: true

# app/helpers/changelog_helper.rb
module ChangelogHelper
  def chibichange_widget_src
    "#{CHIBICHANGE_WIDGET_HOST}/w/v1/loader.js"
  end
end
```

- [ ] **Step 5: Run test, verify pass**

Run: `bundle exec rspec spec/helpers/changelog_helper_spec.rb`
Expected: PASS.

- [ ] **Step 6: Create the prompt partial**

```erb
<%# app/views/shared/navbar/_changelog_prompt.html.erb %>
<%# Polite, non-blocking opt-in. Shown only while consent is pending. %>
<div class="dropdown dropdown-end dropdown-open">
  <div class="card card-compact w-72 bg-base-100 shadow-lg border border-base-300 absolute right-0 mt-2 z-[60]">
    <div class="card-body">
      <h3 class="font-semibold text-sm">Stay up to date?</h3>
      <p class="text-xs opacity-80">
        Show a "What's New" notice when a new Dawarich version ships, including
        security fixes. This checks for updates about once a day and sends only
        your version, app name, and site origin — no IP, no tracking. You can
        change this anytime.
      </p>
      <div class="card-actions justify-end mt-1">
        <%= button_to "No thanks", changelog_consent_path,
              method: :patch, params: { decision: "declined" },
              class: "btn btn-ghost btn-xs",
              form: { data: { turbo_stream: true } } %>
        <%= button_to "Yes, notify me", changelog_consent_path,
              method: :patch, params: { decision: "granted" },
              class: "btn btn-primary btn-xs",
              form: { data: { turbo_stream: true } } %>
      </div>
    </div>
  </div>
</div>
```

- [ ] **Step 7: Create the version-indicator partial (3 states)**

```erb
<%# app/views/shared/navbar/_version_indicator.html.erb %>
<div id="version-indicator" class="relative">
  <% if user_signed_in? && current_user.changelog_consent_granted? %>
    <%# GRANTED: chibichange pill mounts here; native badge suppressed. %>
    <div id="chgtool-mount" class="mx-4 inline-flex items-center"></div>
    <%= javascript_include_tag chibichange_widget_src,
          async: true,
          data: { slug: CHIBICHANGE_SLUG, version: APP_VERSION, consent: "granted", mount: "#chgtool-mount" } %>
  <% else %>
    <%# DECLINED or PENDING: native GitHub-release badge (existing behavior). %>
    <div class="badge mx-4 <%= 'badge-outline' if new_version_available? %>">
      <a href="https://github.com/Freika/dawarich/releases/latest" target="_blank" class="inline-flex items-center">
        <% if new_version_available? %>
          <span class="tooltip tooltip-bottom" data-tip="New version available! Check out Github releases!">
            <span class="hidden sm:inline"><%= APP_VERSION %>&nbsp;!</span>
          </span>
        <% else %>
          <span class="hidden sm:inline"><%= APP_VERSION %></span>
        <% end %>
      </a>
    </div>
    <% if user_signed_in? && current_user.changelog_prompt_pending? %>
      <%= render "shared/navbar/changelog_prompt" %>
    <% end %>
  <% end %>
</div>
```

- [ ] **Step 8: Wire it into the navbar**

Replace `app/views/shared/_navbar.html.erb` lines 56–66 (the inline `<div class="badge ...">...</div>` block) with:

```erb
    <%= render "shared/navbar/version_indicator" %>
```

- [ ] **Step 9: Verify the suite + render**

Run: `bundle exec rspec spec/helpers/changelog_helper_spec.rb spec/requests/settings_spec.rb spec/models/user_spec.rb`
Expected: all PASS. Then boot the app and confirm the three states render (see Task: Verify).

- [ ] **Step 10: Commit** (only on explicit user instruction)

---

## Self-Review

- **Spec coverage:** prompt-once (nil → prompt) ✓ Task 3 Step 7; record in DB ✓ Tasks 1–2; granted → script/pill ✓ Task 3; declined/pending → bang ✓ Task 3; data-consent passed to widget ✓ Task 3 Step 7.
- **Type consistency:** `changelog_consent_granted?` / `changelog_consent_declined?` (enum prefix) used identically in model, controller, views. `#version-indicator` dom id matches turbo_stream target. `chibichange_widget_src` defined once, used once.
- **Phone-home guarantee:** script tag rendered ONLY in the `granted` branch → declined/pending users never fetch `loader.js`.
- **Note:** `CheckAppVersion#call` returns `false` in production today, so the native bang is effectively dev/self-host-visible only. Out of scope — existing behavior preserved, not modified.
