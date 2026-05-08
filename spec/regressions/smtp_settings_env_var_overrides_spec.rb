# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'production environment SMTP and mailer URL config' do
  let(:source) { File.read(Rails.root.join('config/environments/production.rb')) }

  it 'reads SMTP authentication from env with :plain default' do
    expect(source).to match(/ENV\.fetch\(['"]SMTP_AUTHENTICATION['"],\s*['"]plain['"]\)\.to_sym/)
  end

  it 'reads SMTP open and read timeouts from env with 5s defaults' do
    expect(source).to match(/ENV\.fetch\(['"]SMTP_OPEN_TIMEOUT['"],\s*['"]5['"]\)\.to_i/)
    expect(source).to match(/ENV\.fetch\(['"]SMTP_READ_TIMEOUT['"],\s*['"]5['"]\)\.to_i/)
  end

  it 'reads mailer URL protocol from env with https default' do
    expect(source).to match(/ENV\.fetch\(['"]APPLICATION_PROTOCOL['"],\s*['"]https['"]\)/)
  end

  it 'still reads APPLICATION_HOSTS, DOMAIN, and SMTP_SERVER from env' do
    expect(source).to include("ENV.fetch('APPLICATION_HOSTS', 'localhost')")
    expect(source).to match(/host:\s*ENV\[['"]DOMAIN['"]\]/)
    expect(source).to match(/address:\s*ENV\[['"]SMTP_SERVER['"]\]/)
  end
end
