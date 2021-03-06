require 'jetspider/ast'
require 'jetspider/exception'
require 'pp'

module JetSpider
  class CodeGenerator < AstVisitor
    def initialize(object_file)
      @object_file = object_file
      @asm = nil

      @loop_break_loc = []
      @loop_continue_loc = []
    end

    def generate_object_file(ast)
      @compiling_toplevel = false
      ast.global_functions.each do |fun|
        compile_function fun
      end
      compile_toplevel ast
      @object_file
    end

    def compile_function(fun)
      open_asm_writer(fun.scope, fun.filename, fun.lineno) {
        visit fun.function_body.value
      }
    end

    def compile_toplevel(ast)
      open_asm_writer(ast.global_scope, ast.filename, ast.lineno) {
        @compiling_toplevel = true
        traverse_ast(ast)
        @compiling_toplevel = false
      }
    end

    def open_asm_writer(*unit_args)
      unit = @object_file.new_unit(*unit_args)
      @asm = Assembler.new(unit)
      yield
      @asm.stop
    ensure
      @asm = nil
    end

    #
    # Declarations & Statements
    #

    def visit_SourceElementsNode(node)
      node.value.each do |n|
        visit n
      end
    end

    def visit_ExpressionStatementNode(node)
      visit node.value
      pop_statement_value
    end

    def pop_statement_value
      if @compiling_toplevel
        @asm.popv
      else
        @asm.pop
      end
    end

    def visit_EmptyStatementNode(n)
      # We can silently remove
    end

    def visit_BlockNode(n)
      visit n.value
    end

    def visit_CommaNode(n)
      visit n.left
      @asm.pop
      visit n.value
    end

    #
    # Functions-related
    #

    def visit_FunctionCallNode(n)
      @asm.callgname(n.value.value)
      n.arguments.value.each do |arg|
        visit arg
      end
      @asm.call(n.arguments.value.length)
    end

    def visit_FunctionDeclNode(n)
      unless @compiling_toplevel
        raise SemanticError, "nested function not implemented yet"
      end
      # Function declarations are compiled in other step,
      # we just ignore them while compiling toplevel.
    end

    def visit_FunctionExprNode(n) raise "FunctionExprNode not implemented"; end

    def visit_ReturnNode(n)
      visit n.value
      @asm.return
    end

    # These nodes should not be visited directly
    def visit_ArgumentsNode(n) raise "[FATAL] ArgumentsNode visited"; end
    def visit_FunctionBodyNode(n) raise "[FATAL] FunctionBodyNode visited"; end
    def visit_ParameterNode(n) raise "[FATAL] ParameterNode visited"; end

    #
    # Variables-related
    #

    def visit_ResolveNode(n)
      if n.variable.parameter?
        @asm.getarg n.variable.index
      elsif n.variable.local?
        @asm.getlocal n.variable.index
      else
        @asm.getgname n.value
      end
    end

    def visit_OpEqualNode(n)
      if n.variable.global?
        @asm.bindgname n.left.value
        visit n.value
        @asm.setgname n.left.value
      elsif n.variable.local?
        visit n.value
        @asm.setlocal n.left.value
      else
        raise "Invalid OpEqual"
      end
    end

    def visit_VarStatementNode(n)
      n.value.each do |var|
        visit var
      end
    end

    def visit_VarDeclNode(n)
      if n.variable.global?
        @asm.bindgname n.name
        if n.value
          visit n.value
          @asm.setgname n.name
        else
          @asm.getgname n.name
        end
        @asm.pop
      elsif n.variable.local?
        if n.value
          visit n.value
          @asm.setlocal n.variable.index
        else
          @asm.getlocal n.variable.index
        end
        @asm.pop
      else
        raise "Invalid VarDecl"
      end
    end

    def visit_AssignExprNode(n)
      visit n.value
    end

    # We do not support let, const, with
    def visit_ConstStatementNode(n) raise "ConstStatementNode not implemented"; end
    def visit_WithNode(n) raise "WithNode not implemented"; end

    def visit_OpPlusEqualNode(n) raise "OpPlusEqualNode not implemented"; end
    def visit_OpMinusEqualNode(n) raise "OpMinusEqualNode not implemented"; end
    def visit_OpMultiplyEqualNode(n) raise "OpMultiplyEqualNode not implemented"; end
    def visit_OpDivideEqualNode(n) raise "OpDivideEqualNode not implemented"; end
    def visit_OpModEqualNode(n) raise "OpModEqualNode not implemented"; end
    def visit_OpAndEqualNode(n) raise "OpAndEqualNode not implemented"; end
    def visit_OpOrEqualNode(n) raise "OpOrEqualNode not implemented"; end
    def visit_OpXOrEqualNode(n) raise "OpXOrEqualNode not implemented"; end
    def visit_OpLShiftEqualNode(n) raise "OpLShiftEqualNode not implemented"; end
    def visit_OpRShiftEqualNode(n) raise "OpRShiftEqualNode not implemented"; end
    def visit_OpURShiftEqualNode(n) raise "OpURShiftEqualNode not implemented"; end

    #
    # Control Structures
    #

    def visit_IfNode(n)
      visit n.conditions
      loc = @asm.lazy_location
      @asm.ifeq loc
      # then
      visit n.value
      if (n.else.nil?)
        @asm.fix_location loc
      else
        loc_endif = @asm.lazy_location
        @asm.goto loc_endif
        @asm.nullblockchain
        # else
        @asm.fix_location(loc)
        visit n.else
        @asm.fix_location(loc_endif)
      end
    end

    def visit_ConditionalNode(n)
      raise NotImplementedError, 'ConditinalNode'
    end

    def visit_WhileNode(n)
      @loop_break_loc.push @asm.lazy_location
      @loop_continue_loc.push @asm.lazy_location

      # jump to condition
      @asm.goto @loop_continue_loc[-1]
      # restart
      restart = @asm.location

      # loop body
      visit n.value

      # condition
      @asm.fix_location @loop_continue_loc.pop
      visit n.left
      @asm.ifne restart

      @asm.fix_location @loop_break_loc.pop
    end

    def visit_DoWhileNode(n)
      raise NotImplementedError, 'DoWhileNode'
    end

    def visit_ForNode(n)
      raise NotImplementedError, 'ForNode'
    end

    def visit_BreakNode(n)
      @asm.goto @loop_break_loc[-1]
    end

    def visit_ContinueNode(n)
      @asm.goto @loop_continue_loc[-1]
    end

    def visit_SwitchNode(n) raise "SwitchNode not implemented"; end
    def visit_CaseClauseNode(n) raise "CaseClauseNode not implemented"; end
    def visit_CaseBlockNode(n) raise "CaseBlockNode not implemented"; end

    def visit_ForInNode(n) raise "ForInNode not implemented"; end
    def visit_InNode(n) raise "InNode not implemented"; end
    def visit_LabelNode(n) raise "LabelNode not implemented"; end

    # We do not support exceptions
    def visit_TryNode(n) raise "TryNode not implemented"; end
    def visit_ThrowNode(n) raise "ThrowNode not implemented"; end

    #
    # Compound Expressions
    #

    def visit_ParentheticalNode(n)
      visit n.value
    end

    #def visit_AddNode(n)
    #  visit n.left
    #  visit n.value
    #  @asm.add
    #end
    #
    #def visit_SubtractNode(n)
    #  visit node.left
    #  visit node.value
    #  @asm.sub
    #end

    def self.simple_binary_op(node_class, insn_name)
      define_method(:"visit_#{node_class}") {|node|
        visit node.left
        visit node.value
        @asm.__send__(insn_name)
      }
    end

    simple_binary_op 'AddNode', :add
    simple_binary_op 'SubtractNode', :sub
    simple_binary_op 'MultiplyNode', :mul
    simple_binary_op 'DivideNode', :div
    simple_binary_op 'ModulusNode', :mod

    def visit_UnaryPlusNode(n)
      raise NotImplementedError, 'UnaryPlusNode'
    end

    def visit_UnaryMinusNode(n)
      raise NotImplementedError, 'UnaryMinusNode'
    end

    def visit_PrefixNode(n)
      raise "PrefixNode not implemented"
    end

    def visit_PostfixNode(n)
      case n.value
      when "++"
        @asm.gnameinc n.operand.value
      when "--"
        @asm.gnamedec n.operand.value
      else
        raise "Invalid unary operator: #{n.value}"
      end
    end

    def visit_BitwiseNotNode(n) raise "BitwiseNotNode not implemented"; end
    def visit_BitAndNode(n) raise "BitAndNode not implemented"; end
    def visit_BitOrNode(n) raise "BitOrNode not implemented"; end
    def visit_BitXOrNode(n) raise "BitXOrNode not implemented"; end
    def visit_LeftShiftNode(n) raise "LeftShiftNode not implemented"; end
    def visit_RightShiftNode(n) raise "RightShiftNode not implemented"; end
    def visit_UnsignedRightShiftNode(n) raise "UnsignedRightShiftNode not implemented"; end

    def visit_TypeOfNode(n) raise "TypeOfNode not implemented"; end

    #
    # Comparison
    #

    simple_binary_op 'EqualNode', :eq
    simple_binary_op 'NotEqualNode', :ne
    simple_binary_op 'StrictEqualNode', :stricteq
    simple_binary_op 'NotStrictEqualNode', :strictne

    simple_binary_op 'GreaterNode', :gt
    simple_binary_op 'GreaterOrEqualNode', :ge
    simple_binary_op 'LessNode', :lt
    simple_binary_op 'LessOrEqualNode', :le

    simple_binary_op 'LogicalAndNode', :and
    simple_binary_op 'LogicalOrNode', :or

    def visit_LogicalNotNode(n) raise "LogicalNotNode not implemented"; end

    #
    # Object-related
    #

    def visit_NewExprNode(n)
      raise NotImplementedError, 'NewExprNode'
    end

    def visit_DotAccessorNode(n)
      raise NotImplementedError, 'DotAccessorNode'
    end

    def visit_BracketAccessorNode(n)
      raise NotImplementedError, 'BracketAccessorNode'
    end

    def visit_InstanceOfNode(n) raise "InstanceOfNode not implemented"; end
    def visit_AttrNode(n) raise "AttrNode not implemented"; end
    def visit_DeleteNode(n) raise "DeleteNode not implemented"; end
    def visit_PropertyNode(n) raise "PropertyNode not implemented"; end
    def visit_GetterPropertyNode(n) raise "GetterPropertyNode not implemented"; end
    def visit_SetterPropertyNode(n) raise "SetterPropertyNode not implemented"; end

    #
    # Primitive Expressions
    #

    def visit_NullNode(n)
      @asm.null
    end

    def visit_TrueNode(n)
      @asm.true
    end

    def visit_FalseNode(n)
      @asm.false
    end

    def visit_ThisNode(n)
      @asm.this
    end

    def visit_NumberNode(n)
      @asm.int(n.value)
    end

    def visit_StringNode(n)
      raise "Non quoted string given" if n.value.length < 2
      @asm.string(n.value[1 .. n.value.length-2])
    end

    def visit_ArrayNode(n) raise "ArrayNode not implemented"; end
    def visit_ElementNode(n) raise "ElementNode not implemented"; end

    def visit_RegexpNode(n) raise "RegexpNode not implemented"; end

    def visit_ObjectLiteralNode(n) raise "ObjectLiteralNode not implemented"; end

    def visit_VoidNode(n) raise "VoidNode not implemented"; end
  end
end
