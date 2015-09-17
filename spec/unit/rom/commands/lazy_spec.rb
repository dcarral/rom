require 'spec_helper'

describe ROM::Commands::Lazy do
  let(:rom) { setup.finalize }
  let(:setup) { ROM.setup(:memory) }

  let(:create_user) { rom.command(:users).create }
  let(:update_user) { rom.command(:users).update }
  let(:delete_user) { rom.command(:users).delete }

  let(:create_task) { rom.command(:tasks).create }
  let(:create_tasks) { rom.command(:tasks).create_many }
  let(:update_task) { rom.command(:tasks).update }

  let(:input) { { user: { name: 'Jane', email: 'jane@doe.org' } } }
  let(:jane) { input[:user] }
  let(:evaluator) { -> input { input[:user] } }

  before do
    setup.relation(:tasks) do
      def by_user_and_title(user, title)
        by_user(user).by_title(title)
      end

      def by_user(user)
        restrict(user: user)
      end

      def by_title(title)
        restrict(title: title)
      end
    end

    setup.relation(:users) do
      def by_name(name)
        restrict(name: name)
      end
    end

    setup.commands(:users) do
      define(:create) do
        result :one
      end

      define(:update) do
        result :one
      end

      define(:delete) do
        result :one
      end
    end

    setup.commands(:tasks) do
      define(:create) do
        result :one
      end

      define(:create_many, type: :create) do
        def execute(tuples, user)
          super(tuples.map { |tuple| tuple.merge(user: user[:name]) })
        end
      end

      define(:update) do
        result :one

        def execute(tuple, user)
          super(tuple.merge(user: user[:name]))
        end
      end
    end
  end

  describe '#call' do
    context 'with a create command' do
      subject(:command) { ROM::Commands::Lazy.new(create_user, evaluator) }

      it 'evaluates the input and calls command' do
        command.call(input)

        expect(rom.relation(:users)).to match_array([jane])
      end
    end

    context 'with a create command for many child tuples' do
      subject(:command) do
        ROM::Commands::Lazy.new(create_tasks, evaluator)
      end

      let(:evaluator) { -> input, index { input[:users][index][:tasks] } }

      let(:input) do
        { users: [
          {
            name: 'Jane',
            tasks: [{ title: 'Jane Task One' }, { title: 'Jane Task Two' }]
          },
          {
            name: 'Joe',
            tasks: [{ title: 'Joe Task One' }]
          }
        ]}
      end

      it 'evaluates the input and calls command' do
        command.call(input, input[:users])

        expect(rom.relation(:tasks)).to match_array([
          { user: 'Jane', title: 'Jane Task One' },
          { user: 'Jane', title: 'Jane Task Two' },
          { user: 'Joe', title: 'Joe Task One' }
        ])
      end
    end

    context 'with an update command' do
      subject(:command) do
        ROM::Commands::Lazy.new(update_user, evaluator, [:by_name, ['user.name']])
      end

      before do
        create_user[jane]
      end

      it 'evaluates the input, restricts the relation and calls its command' do
        input = { user: { name: 'Jane', email: 'jane.doe@rom-rb.org' } }
        command.call(input)

        expect(rom.relation(:users)).to match_array([input[:user]])
      end
    end

    context 'with an update command for a child tuple' do
      subject(:command) do
        ROM::Commands::Lazy.new(
          update_task,
          evaluator,
          [:by_user_and_title, ['user.name', 'user.task.title']]
        )
      end

      let(:evaluator) { -> input { input[:user][:task] } }

      let(:jane) { { name: 'Jane' } }
      let(:jane_task) { { user: 'Jane', title: 'Jane Task', priority: 1 } }

      let(:input) { { user: jane.merge(task: jane_task) } }

      before do
        create_user[jane]
        create_task[user: 'Jane', title: 'Jane Task', priority: 2]
      end

      it 'evaluates the input, restricts the relation and calls its command' do
        command.call(input, input[:user])

        expect(rom.relation(:users)).to match_array([jane])

        expect(rom.relation(:tasks)).to match_array([jane_task])
      end
    end

    context 'with an update command for child tuples' do
      subject(:command) do
        ROM::Commands::Lazy.new(
          update_task,
          evaluator,
          [:by_user_and_title, ['user.name', 'user.tasks.title']]
        )
      end

      let(:evaluator) { -> input { input[:user][:tasks] } }

      let(:jane) { { name: 'Jane' } }
      let(:jane_tasks) {
        [
          { user: 'Jane', title: 'Jane Task One', priority: 2 },
          { user: 'Jane', title: 'Jane Task Two', priority: 3 }
        ]
      }

      let(:input) { { user: jane.merge(tasks: jane_tasks) } }

      before do
        create_user[jane]
        create_task[user: 'Jane', title: 'Jane Task One', priority: 3]
        create_task[user: 'Jane', title: 'Jane Task Two', priority: 4]
      end

      it 'evaluates the input, restricts the relation and calls its command' do
        command.call(input, input[:user])

        expect(rom.relation(:users)).to match_array([jane])

        expect(rom.relation(:tasks)).to match_array(jane_tasks)
      end
    end

    context 'with a delete command' do
      subject(:command) do
        ROM::Commands::Lazy.new(delete_user, evaluator, [:by_name, ['user.name']])
      end

      let(:joe) { { name: 'Joe' } }

      before do
        create_user[jane]
        create_user[joe]
      end

      it 'restricts the relation and calls its command' do
        command.call(input)

        expect(rom.relation(:users)).to match_array([joe])
      end
    end
  end

  describe '#>>' do
    subject(:command) { ROM::Commands::Lazy.new(create_user, evaluator) }

    it 'composes with another command' do
      expect(command >> create_task).to be_instance_of(ROM::Commands::Composite)
    end
  end

  describe '#combine' do
    subject(:command) { ROM::Commands::Lazy.new(create_user, evaluator) }

    it 'combines with another command' do
      expect(command.combine(create_task)).to be_instance_of(ROM::Commands::Graph)
    end
  end

  describe '#method_missing' do
    subject(:command) { ROM::Commands::Lazy.new(update_user, evaluator) }

    it 'forwards to command' do
      rom.relations[:users] << { name: 'Jane' } << { name: 'Joe' }

      new_command = command.by_name('Jane')
      new_command.call(user: { name: 'Jane Doe' })

      expect(rom.relation(:users)).to match_array([
        { name: 'Jane Doe' },
        { name: 'Joe' }
      ])
    end

    it 'returns original response if it was not a command' do
      response = command.result
      expect(response).to be(:one)
    end

    it 'raises error when message is unknown' do
      expect { command.not_here }.to raise_error(NoMethodError, /not_here/)
    end
  end
end
