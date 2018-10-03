class Fixture
  attr_reader :computations

  include Kaicho

  def initialize
    def_resource(:apples, accessor: :both) { @apples || 0 }
    def_resource(:oranges, accessor: :both) { @oranges || 0 }
    def_resource(:total, depends: { apples: :fail, oranges: :fail }) do
      @computations += 1
      @apples + @oranges
    end

    @computations = 0
  end
end

RSpec.describe Kaicho do
  context 'fruit example' do

    f = Fixture.new

    it 'has accessors' do
      expect(f).to respond_to :apples
      expect(f).to respond_to :apples=
      expect(f).to respond_to :oranges
      expect(f).to respond_to :oranges=
    end

    it 'can use accessors' do
      expect(f.apples).to eq 0
      f.apples += 1
      expect(f.apples).to eq 1

      expect(f.oranges).to eq 0
      f.oranges += 1
      expect(f.oranges).to eq 1
    end

    it 'automatically updates' do
      10.times { f.total }
      expect(f.total).to eq 2
      expect(f.computations).to eq 2
    end
  end
end
