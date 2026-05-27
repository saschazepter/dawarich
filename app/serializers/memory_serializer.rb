# frozen_string_literal: true

# Wraps the Memories::Builder output in the shape the Map v2 _memories_reel
# partial reads (`{ anchor:, chapters: [...] }`).
class MemorySerializer
  def initialize(user, anchor: Time.current)
    @user = user
    @anchor = anchor
  end

  def call
    chapters = Memories::Builder.new(@user, anchor: @anchor).call
    {
      anchor: @anchor.to_date.iso8601,
      chapters: chapters
    }
  end
end
