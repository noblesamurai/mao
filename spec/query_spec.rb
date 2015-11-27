# encoding: utf-8
require 'spec_helper'

describe Mao::Query do
  before { prepare_spec }

  let(:empty) { Mao.query(:empty) }
  let(:one) { Mao.query(:one) }
  let(:some) { Mao.query(:some) }
  let(:typey) { Mao.query(:typey) }
  let(:autoid) { Mao.query(:autoid) }
  let(:times) { Mao.query(:times) }

  describe ".new" do
    subject { Mao::Query.new(:table, {}, {}) }

    its(:table) { should be_an_instance_of Symbol }
    its(:options) { should be_frozen }
    its(:col_types) { should be_frozen }

    context "no such table" do
      it { expect { Mao::Query.new("nonextant")
                  }.to raise_exception(ArgumentError) }
    end
  end

  describe "#with_options" do
    subject { one.with_options(:blah => 99) }

    its(:table) { should be one.table }
    its(:options) { should eq({:blah => 99}) }
  end

  describe "#limit" do
    subject { some.limit(2) }

    its(:options) { should include(:limit => 2) }
    its(:sql) { should eq 'SELECT * FROM "some" LIMIT 2' }

    context "invalid argument" do
      it { expect { some.limit("2")
                  }.to raise_exception(ArgumentError) }

      it { expect { some.limit(false)
                  }.to raise_exception(ArgumentError) }
    end
  end

  describe "#order" do
    let(:asc) { some.order(:id, :asc) }
    it { asc.options.should include(:order => [:id, 'ASC']) }
    it { asc.sql.should eq 'SELECT * FROM "some" ORDER BY "id" ASC' }

    let(:desc) { one.order(:value, :desc) }
    it { desc.options.should include(:order => [:value, 'DESC']) }
    it { desc.sql.should eq 'SELECT * FROM "one" ORDER BY "value" DESC' }

    it { expect { one.order(:huh, :asc) }.to raise_exception(ArgumentError) }
    it { expect { one.order(:value) }.to raise_exception(ArgumentError) }
    it { expect { one.order(:id, 'ASC') }.to raise_exception(ArgumentError) }
    it { expect { one.order(:id, :xyz) }.to raise_exception(ArgumentError) }
  end

  describe "#only" do
    subject { some.only(:id, [:value]) }

    its(:options) { should include(:only => [:id, :value]) }
    its(:sql) { should eq 'SELECT "id", "value" FROM "some"' }

    context "invalid argument" do
      it { expect { some.only(42)
                  }.to raise_exception(ArgumentError) }

      it { expect { some.only(nil)
                  }.to raise_exception(ArgumentError) }

      it { expect { some.only("id")
                  }.to raise_exception(ArgumentError) }

      it { expect { some.only(:j)
                  }.to raise_exception(ArgumentError) }
    end

    context "with #join" do
      subject { some.join(:one) { one.value == some.value }.
                    only(:one => [:id]) }

      its(:options) { should include(:only => {:one => [:id]}) }
      its(:sql) { should eq 'SELECT "one"."id" "c3" ' +
                            'FROM "some" ' +
                            'INNER JOIN "one" ' +
                            'ON ("one"."value" = "some"."value")' }
      its(:select!) { should eq [{:one => {:id => 42}}] }

      context "before #join" do
        it { expect { some.only(:some => [:id])
                    }.to raise_exception(ArgumentError) }
      end

      context "poor arguments" do
        it { expect { some.join(:one) { one.value }.only(:some => :id)
                    }.to raise_exception(ArgumentError) }
      end
    end
  end

  describe "#returning" do
    subject { some.returning([:id], :value).
                  with_options(:insert => [{:value => "q"}]) }

    its(:options) { should include(:returning => [:id, :value]) }
    its(:sql) { should eq 'INSERT INTO "some" ("value") ' +
                          'VALUES (\'q\') RETURNING "id", "value"' }

    context "invalid argument" do
      it { expect { some.returning(42)
                  }.to raise_exception(ArgumentError) }

      it { expect { some.returning(nil)
                  }.to raise_exception(ArgumentError) }

      it { expect { some.returning("id")
                  }.to raise_exception(ArgumentError) }

      it { expect { some.returning("j")
                  }.to raise_exception(ArgumentError) }
    end
  end

  describe "#where" do
    subject { some.where { (id == 1).or(id > 10_000) } }
    
    its(:options) do
      should include(:where => [:Binary,
                                'OR',
                                [:Binary, '=', [:Column, :id], "1"],
                                [:Binary, '>', [:Column, :id], "10000"]])
    end

    its(:sql) { should eq 'SELECT * FROM "some" WHERE ' \
                          '(("id" = 1) OR ("id" > 10000))' }

    context "non-extant column" do
      it { expect { some.where { non_extant_column == 42 }
                  }.to raise_exception(ArgumentError) }
    end

    context "with #join" do
      subject { some.join(:one) { one.value == some.value }.
                    where { one.id == 42 } }

      its(:options) { should include(:where => [:Binary,
                                                '=',
                                                [:Column, :one, :id],
                                                "42"]) }
      its(:sql) { should eq 'SELECT "some"."id" "c1", ' +
                            '"some"."value" "c2", ' +
                            '"one"."id" "c3", ' +
                            '"one"."value" "c4" ' +
                            'FROM "some" ' +
                            'INNER JOIN "one" ' +
                            'ON ("one"."value" = "some"."value") ' +
                            'WHERE ("one"."id" = 42)' }

      its(:select!) { should eq(
                          [{:some => {:id => 3, :value => "你好, Dave."},
                            :one => {:id => 42, :value => "你好, Dave."}}]) }
    end

    context "with time values" do
      it { times.select_first!.should eq(
               {:id => 1, :time => Time.new(2012, 11, 10, 19, 45, 0, 0)}) }

      it { times.where { time == Time.new(2012, 11, 11, 6, 45, 0, 11 * 3600) }.
               select!.length.should eq 1 }
      it { times.where { time == Time.new(2012, 11, 10, 19, 45, 0, 0) }.
               select!.length.should eq 1 }
      it { times.where { time == "2012-11-10 19:45:00" }.
               select!.length.should eq 1 }
      it { times.where { time == "2012-11-10 19:45:00 Z" }.
               select!.length.should eq 1 }
      it { times.where { time == "2012-11-10 19:45:00 +00" }.
               select!.length.should eq 1 }
      it { times.where { time == "2012-11-10 19:45:00 +00:00" }.
               select!.length.should eq 1 }
      it { times.where { time == "2012-11-10 19:45:00 -00" }.
               select!.length.should eq 1 }
      it { times.where { time == "2012-11-10 19:45:00 -00:00" }.
               select!.length.should eq 1 }

      it { times.where { time < Time.new(2012, 11, 11, 6, 45, 0, 11 * 3600) }.
               select!.length.should eq 0 }
      context "surprising results" do
        # Timestamps are IGNORED for comparisons with "timestamp without time
        # zone".  See:
        # http://postgresql.org/docs/9.1/static/datatype-datetime.html#AEN5714
        it { times.where { time < "2012-11-11 6:45:00 +11" }.
                 select!.length.should eq 1 }
        it { times.where { time < "2012-11-11 6:45:00 +1100" }.
                 select!.length.should eq 1 }
        it { times.where { time < "2012-11-11 6:45:00 +11:00" }.
                 select!.length.should eq 1 }
      end
      it { times.where { time <= Time.new(2012, 11, 11, 6, 45, 0, 11 * 3600) }.
               select!.length.should eq 1 }
      it { times.where { time <= "2012-11-11 6:45:00 +11" }.
               select!.length.should eq 1 }
      it { times.where { time <= "2012-11-11 6:45:00 +1100" }.
               select!.length.should eq 1 }
      it { times.where { time <= "2012-11-11 6:45:00 +11:00" }.
               select!.length.should eq 1 }
    end
  end

  describe "#join" do
    subject { some.join(:one) { one.value == some.value } }

    its(:options) do
      should include(:join => [:one,
                               [:Binary,
                                '=',
                                [:Column, :one, :value],
                                [:Column, :some, :value]]])
    end

    its(:sql) { should eq(
      'SELECT ' +
      '"some"."id" "c1", ' +
      '"some"."value" "c2", ' +
      '"one"."id" "c3", ' +
      '"one"."value" "c4" ' +
      'FROM "some" ' +
      'INNER JOIN "one" ' +
      'ON ("one"."value" = "some"."value")') }

    its(:select!) { should eq [{:some => {:id => 3,
                                          :value => "你好, Dave."},
                                :one => {:id => 42,
                                          :value => "你好, Dave."}}] }

    context "simple Hash joins" do
      subject { some.join({:one => {:value => :id}}) }

      its(:options) do
        should include(:join => [:one,
                                 [:Binary,
                                  '=',
                                  [:Column, :some, :value],
                                  [:Column, :one, :id]]])
      end
    end
  end

  describe "#select!" do
    context "use of #sql" do
      # HACK: construct empty manually, otherwise it'll try to look up column
      # info and ruin our assertions.
      let(:empty) { Mao::Query.new("empty",
                                    {},
                                    {}) }
      let(:empty_sure) { double("empty_sure") }
      let(:empty_sql) { double("empty_sql") }
      before { empty.should_receive(:with_options).
                   with(:update => nil).
                   and_return(empty_sure) }
      before { empty_sure.should_receive(:sql).
                   and_return(empty_sql) }
      before { PG::Connection.any_instance.should_receive(:exec).
                   with(empty_sql).and_return(:ok) }
      it { empty.select!.should eq :ok }
    end

    context "no results" do
      it { empty.select!.should eq [] }
    end

    context "one result" do
      subject { one.select! }

      it { should be_an_instance_of Array }
      it { should have(1).item }
      its([0]) { should eq({:id => 42, :value => "你好, Dave."}) }
    end

    context "some results" do
      subject { some.select! }

      it { should be_an_instance_of Array }
      it { should have(3).items }

      its([0]) { should eq({:id => 1, :value => "Bah"}) }
      its([1]) { should eq({:id => 2, :value => "Hah"}) }
      its([2]) { should eq({:id => 3, :value => "你好, Dave."}) }
    end

    context "various types" do
      subject { typey.select! }

      it { should have(2).items }
      its([0]) { should eq(
        {:korea => true,
         :japan => BigDecimal.new("1234567890123456.789"),
         :china => "WHAT\x00".force_encoding(Encoding::ASCII_8BIT)}) }
      its([1]) { should eq(
        {:korea => false,
         :japan => BigDecimal.new("-1234567890123456.789"),
         :china => "HUH\x01\x02".force_encoding(Encoding::ASCII_8BIT)}) }
    end
  end

  describe "#select_first!" do
    # HACK: construct empty manually, otherwise it'll try to look up column
    # info and ruin our assertions.
    let(:empty) { Mao::Query.new("empty",
                                  {},
                                  {}) }
    before { empty.should_receive(:limit).with(1).and_return(empty) }
    before { empty.should_receive(:select!).and_return([:ok]) }
    it { empty.select_first!.should eq :ok }
  end

  describe "#update!" do
    context "use of #sql" do
      let(:empty) { Mao::Query.new("empty",
                                    {},
                                    {}) }
      let(:empty_update) { double("empty_update") }
      let(:empty_sql) { double("empty_sql") }
      before { empty.should_receive(:with_options).
                   with(:update => {:x => :y}).
                   and_return(empty_update) }
      before { empty_update.should_receive(:sql).and_return(empty_sql) }
      before { PG::Connection.any_instance.should_receive(:exec).
                   with(empty_sql).and_return(:ok) }
      it { empty.update!(:x => :y).should eq :ok }
    end

    context "#sql result" do
      subject { empty.with_options(:update => {:id => 44}).sql }
      it { should eq 'UPDATE "empty" SET "id" = 44' }
    end

    context "no matches" do
      it { empty.update!(:value => "y").should eq 0 }
    end

    context "no such column" do
      it { expect { empty.update!(:x => "y")
                  }.to raise_exception(ArgumentError, /is not a column/) }
    end

    context "some matches" do
      it { some.where { id <= 2 }.update!(:value => 'Meh').should eq 2 }
    end
  end

  describe "#insert!" do
    context "use of #sql" do
      let(:empty) { Mao::Query.new("empty",
                                    {},
                                    {}) }
      let(:empty_insert) { double("empty_insert") }
      let(:empty_sql) { double("empty_sql") }
      before { empty.should_receive(:with_options).
                   with(:insert => [{:x => :y}]).
                   and_return(empty_insert) }
      before { empty_insert.should_receive(:sql).and_return(empty_sql) }
      before { PG::Connection.any_instance.should_receive(:exec).
                   with(empty_sql).and_return(:ok) }
      it { empty.insert!([:x => :y]).should eq :ok }
    end

    context "#sql result" do
      context "all columns alike" do
        subject { empty.with_options(
                      :insert => [{:id => 44}, {:id => 38}]).sql }
        it { should eq 'INSERT INTO "empty" ("id") VALUES (44), (38)' }
      end

      context "not all columns alike" do
        subject { empty.with_options(
                      :insert => [{:id => 1}, {:value => 'z', :id => 2}]).sql }
        it { should eq 'INSERT INTO "empty" ("id", "value") ' +
                       'VALUES (1, DEFAULT), (2, \'z\')' }
      end
    end

    context "result" do
      context "number of rows" do
        it { autoid.insert!(:value => "quox").should eq 1 }
        it { autoid.insert!({:value => "lol"}, {:value => "x"}).should eq 2 }
      end

      context "#returning" do
        it do
          autoid.returning(:id).insert!(:value => "nanana").
              should eq([{:id => 1}])
          autoid.returning(:id).insert!(:value => "ha").
              should eq([{:id => 2}])
          autoid.returning(:id).insert!(:value => "bah").
              should eq([{:id => 3}])
          autoid.returning(:id).insert!({:value => "a"}, {:value => "b"}).
              should eq([{:id => 4}, {:id => 5}])
        end
      end
    end
  end

  describe "reconnection" do
    it do
      Mao.query(:one).select!.should be_an_instance_of Array
      pending
    end
  end
end

# vim: set sw=2 cc=80 et: