class FruitFarm
  include Kaicho

  attr_reader :computations

  def initialize
    @computations = 0
    @apple_trees  = 2
    @orange_trees = 1
    super
  end

  def_resource :apple_trees, accessors: :both
  def_resource :orange_trees, accessors: :both

  def_resource :apples, depends: { apple_trees: :fail } do
    @apple_trees * 15
  end

  def_resource :oranges, depends: { orange_trees: :fail } do
    @orange_trees * 25
  end

  def_resource :total, depends: { apples: :keep, oranges: :keep } do
    @computations += 1
    @apples + @oranges
  end
end

RSpec.describe FruitFarm do
  context 'more advanced usage' do
    f = FruitFarm.new

    it 'has accessors' do
      expect(f).to respond_to :apples
      expect(f).not_to respond_to :apples=
      expect(f).to respond_to :apple_trees
      expect(f).to respond_to :apple_trees=
      expect(f).to respond_to :oranges
      expect(f).not_to respond_to :oranges=
      expect(f).to respond_to :orange_trees=
    end

    it 'can compute the total' do
      # 1st computation
      expect(f.total).to eq 55
    end

    it 'can use accessors' do
      expect(f.apple_trees).to eq 2
      expect(f.orange_trees).to eq 1

      expect(f.apples).to eq 30
      # 2nd computation
      f.apple_trees += 1
      expect(f.apples).to eq 45

      expect(f.oranges).to eq 25
      # 3rd computation
      f.orange_trees += 1
      expect(f.oranges).to eq 50

      expect(f.apple_trees).to eq 3
      expect(f.orange_trees).to eq 2
    end

    it 'automatically updates' do
      10.times { f.total }
      expect(f.total).to eq 95
      expect(f.computations).to eq 3
    end
  end
end
