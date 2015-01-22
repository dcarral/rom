require 'rom/lint/repository'
require 'rom/lint/enumerable_dataset'

module ROM
  module Lint
    module Test
      def define_test_method(name, &block)
        define_method "test_#{name}" do
          begin
            instance_eval(&block)
          rescue ROM::Lint::Linter::Failure => f
            raise Minitest::Assertion, f.message
          end
        end
      end
    end

    # This is a simple lint-test for repository class to ensure the
    # basic interfaces are in place
    #
    # @example
    #
    #   class MyRepoTest < Minitest::Test
    #     include ROM::Lint::TestRepository
    #
    #     def setup
    #       @repository = MyRepository
    #       @uri = "super_db://something"
    #     end
    #   end
    #
    # @public
    module TestRepository
      extend ROM::Lint::Test

      attr_reader :repository, :uri

      ROM::Lint::Repository.each_lint do |name, linter|
        define_test_method name do
          assert linter.new(repository, uri).lint(name)
        end
      end
    end

    # This is a simple lint-test for an repository dataset class to ensure the
    # basic behavior is correct
    #
    # @example
    #
    #  class MyDatasetLintTest < Minitest::Test
    #    include ROM::Repository::Lint::TestEnumerableDataset
    #
    #     def setup
    #       @data  = [{ name: 'Jane', age: 24 }, { name: 'Joe', age: 25 }]
    #       @dataset = MyDataset.new(@data, [:name, :age])
    #     end
    #   end
    # @public
    module TestEnumerableDataset
      extend ROM::Lint::Test

      attr_reader :dataset, :data

      ROM::Lint::EnumerableDataset.each_lint do |name, linter|
        define_test_method name do
          assert linter.new(dataset, data).lint(name)
        end
      end
    end
  end
end
