import React, { useState, useEffect } from 'react';
import { fetchTodos, createTodo, toggleTodo, deleteTodo } from './api/todos';
import './App.css';

function App() {
  const [todos, setTodos] = useState([]);
  const [input, setInput] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    loadTodos();
  }, []);

  const loadTodos = async () => {
    try {
      setLoading(true);
      const data = await fetchTodos();
      setTodos(data);
    } catch (err) {
      setError('Failed to connect to server.');
    } finally {
      setLoading(false);
    }
  };

  const handleAdd = async (e) => {
    e.preventDefault();
    if (!input.trim()) return;
    try {
      const newTodo = await createTodo(input.trim());
      setTodos([newTodo, ...todos]);
      setInput('');
    } catch (err) {
      setError('Failed to add todo.');
    }
  };

  const handleToggle = async (id) => {
    try {
      const updated = await toggleTodo(id);
      setTodos(todos.map((t) => (t._id === id ? updated : t)));
    } catch (err) {
      setError('Failed to update todo.');
    }
  };

  const handleDelete = async (id) => {
    try {
      await deleteTodo(id);
      setTodos(todos.filter((t) => t._id !== id));
    } catch (err) {
      setError('Failed to delete todo.');
    }
  };

  const pending = todos.filter((t) => !t.completed).length;
  const done = todos.filter((t) => t.completed).length;

  return (
    <div className="app">
      <div className="container">
        <header className="header">
          <div className="header-top">
            <span className="tag">MERN STACK</span>
          </div>
          <h1 className="title">Task<span>Flow</span></h1>
          <p className="subtitle">Infrastructure-deployed productivity</p>
        </header>

        <div className="stats">
          <div className="stat">
            <span className="stat-num">{pending}</span>
            <span className="stat-label">Pending</span>
          </div>
          <div className="stat-divider" />
          <div className="stat">
            <span className="stat-num">{done}</span>
            <span className="stat-label">Done</span>
          </div>
          <div className="stat-divider" />
          <div className="stat">
            <span className="stat-num">{todos.length}</span>
            <span className="stat-label">Total</span>
          </div>
        </div>

        <form className="form" onSubmit={handleAdd}>
          <input
            className="input"
            type="text"
            placeholder="Add a new task..."
            value={input}
            onChange={(e) => setInput(e.target.value)}
          />
          <button className="btn-add" type="submit">+</button>
        </form>

        {error && <div className="error">{error} <button onClick={() => setError(null)}>✕</button></div>}

        <div className="list">
          {loading ? (
            <div className="empty">Loading tasks...</div>
          ) : todos.length === 0 ? (
            <div className="empty">No tasks yet. Add one above.</div>
          ) : (
            todos.map((todo) => (
              <div key={todo._id} className={`todo-item ${todo.completed ? 'completed' : ''}`}>
                <button
                  className={`checkbox ${todo.completed ? 'checked' : ''}`}
                  onClick={() => handleToggle(todo._id)}
                >
                  {todo.completed ? '✓' : ''}
                </button>
                <span className="todo-title">{todo.title}</span>
                <button className="btn-delete" onClick={() => handleDelete(todo._id)}>✕</button>
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  );
}

export default App;
