module BullsTools

  module Cmd

    def run_cmd(cmd)
      puts nil, cmd
      out = `#{cmd}`
      puts out.gsub(/^/,"  ...\t") unless out == ''
      raise "Failure while trying to run '#{cmd}': #{$?}" unless $?.success?
      out
    end


    class << self

      def check_args_for_help(msg, args=nil)
        args ||= ARGV
        unless (args & ['help', '--help', '-h', '-help']).empty?
          puts msg
          exit
        end
      end

    end # class << self

  end

  module Git

    class << self
      include Cmd

      def force_push_safely(local=nil, remote=nil, repo=nil)
        local, remote, repo = default_branch_params(local, remote, repo)

        # Get the latest updates from the remote repo.
        run_cmd("git fetch #{repo} #{remote}")

        # Look for the last commit in the local branch.
        remote_tip = log_commit_for_compare(remote, repo)
        tip_found = false
        10.times do |i|
          if remote_tip == log_commit_for_compare(local, nil, i)
            tip_found = true
            break
          end
        end

        unless tip_found
          raise "Unable to find last commit from #{repo}/#{remote} in recent history of '#{local}'."
        end

        # Force push is safe, so do it.
        run_cmd("git push --force #{repo} #{local}:#{remote}")

        puts "\nSuccessfully pushed #{local} to #{repo}/#{remote}."
      end

      def log_commit_for_compare(branch, repo=nil, skip=nil)
        branch = "#{repo}/#{branch}" if repo
        skip ||= 0
        log = run_cmd("git log -1 --skip=#{skip} --format=medium #{branch}")
        log.sub(/^\s*commit\b[^\n]*\n/,'')
      end

      def merge_safely(child, parent=nil, remote=nil)
        parent ||= 'master'
        child, parent, remote = default_branch_params(child, parent, remote)

        git_status = run_cmd("git status -s")
        unless git_status == ''
          raise "Unable to proceed with dirty working directory."
        end

        # Get the latest updates from the remote repo.
        run_cmd("git fetch #{remote} #{parent} #{child}")

        # Create the local child if it doesn't exist.
        branches = run_cmd("git branch --list #{child}")
        has_local = branches.split(/\s+/).include?(child)
        unless has_local
          run_cmd("git branch #{child} #{remote}/#{child}")
        end

        # Check that the local branches have been pushed to the remote repo.
        unless remote_contains_local?(child) && remote_contains_local?(parent)
          raise "You have local commits that have not been pushed to #{remote}."
        end

        # Update the local repo.
        run_cmd("git checkout #{child}")
        run_cmd("git pull --ff-only #{remote} #{child}")

        run_cmd("git checkout #{parent}")
        run_cmd("git pull --ff-only #{remote} #{parent}")

        # Check if the child has already been merged into the parent.
        if remote_contains_local?(child, parent)
          raise "#{child} is already merged into #{parent}."
        end

        # Check that the child is a fast-forward of the parent.
        unless remote_contains_local?(parent, child)
          raise "#{child} is not ahead of #{parent}. Please rebase #{child} first:\n  git checkout #{child} && git rebase #{parent}"
        end

        # Merge the child into the parent.
        commit_msg = "Merge branch '#{child}'"
        commit_msg += " into '#{parent}'" unless parent == 'master'
        run_cmd("git merge --no-ff -m \"#{commit_msg}\" #{child}")

        # Push the merge.
        run_cmd("git push #{remote} #{parent}")

        # Rebase the child branch.
        run_cmd("git checkout #{child}")
        run_cmd("git pull --ff-only #{remote} #{parent}")
        run_cmd("git push #{remote} #{child}")

        # Move back to the parent branch.
        run_cmd("git checkout #{parent}")

        # Kill the local child branch if it was created just for this.
        unless has_local
          run_cmd "git branch -d #{child}"
        end

        puts "\nSuccessfully pulled #{child} into #{parent}."

      rescue => e
        begin
          run_cmd("git status")
        rescue => e2
          puts e2
        end
        raise e
      end

      def remote_contains_local?(local=nil, remote=nil, repo=nil)
        local, remote, repo = default_branch_params(local, remote, repo)
        remote = "#{repo}/#{remote}"
        contained = run_cmd("git branch -r --list --contains #{local} #{remote}")
        branches = contained.split(/\s+/)
        contains = branches.include?(remote)
        puts "\t# #{remote} #{contains ? 'contains' : 'does not contain'} local branch '#{local}'."
        contains
      end

      def current_branch
        run_cmd("git symbolic-ref --short HEAD")
      end

      def default_branch_params(local=nil, remote=nil, repo=nil)
        local ||= current_branch
        remote ||= local
        repo ||= 'origin'
        [local, remote, repo]
      end

    end # class << self

  end

end
