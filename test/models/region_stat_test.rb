require "test_helper"

class RegionStatTest < ActiveSupport::TestCase
  # --- composite primary keys (row 80) ------------------------------------

  test "creates, finds, and updates through the composite PK" do
    stat = RegionStat.create!(region: "EU", year: 2026, visits: 10)
    assert_predicate stat, :persisted?

    found = RegionStat.find_by(region: "EU", year: 2026)
    assert_equal 10, found.visits

    # Tuple find: the PK is [region, year], passed as an array.
    by_pk = RegionStat.find([ "EU", 2026 ])
    assert_equal stat.visits, by_pk.visits

    by_pk.update!(visits: 42)
    assert_equal 42, stat.reload.visits

    by_pk.destroy!
    assert_not RegionStat.exists?(region: "EU", year: 2026)
  end

  test "duplicate composite PK raises RecordNotUnique" do
    RegionStat.create!(region: "US", year: 2026, visits: 1)
    error = assert_raises(ActiveRecord::RecordNotUnique) do
      RegionStat.create!(region: "US", year: 2026, visits: 2)
    end
    assert_match(/region_stats_pkey/, error.message)
  end
end
