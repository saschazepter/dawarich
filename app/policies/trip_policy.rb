# frozen_string_literal: true

class TripPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(user_id: user.id)
    end
  end

  def index?
    true
  end

  def show?
    owner?
  end

  def create?
    true
  end

  def new?
    create?
  end

  def update?
    owner?
  end

  def edit?
    update?
  end

  def destroy?
    owner?
  end

  def recalculate?
    owner?
  end

  private

  def owner?
    record.user_id == user.id
  end
end
