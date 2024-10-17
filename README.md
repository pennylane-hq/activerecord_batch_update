# Batch Update

Update multiple records with different values in an optimized number of queries.

This differs from [activerecord-import](https://github.com/zdennis/activerecord-import) because the latter issues a `INSERT ... ON DUPLICATE KEY UPDATE` statement which re-inserts the record if it happens to have been deleted in a other thread.

## Usage
Include in your Gemfile: `gem 'batch_update'`

```ruby
cat1 = Cat.create!(name: 'Felix', birthday: '1990-03-13')
cat2 = Cat.create!(name: 'Garfield', birthday: '1978-06-19')
cat3 = Cat.create!(name: 'Daisy', birthday: '1970-01-01')

cat1.birthday = '2024-01-01'
cat2.birthday = '2024-06-06'
cat3.birthday = '1900-01-01'

Cat.batch_update([cat1, cat2, cat3]) # issues a single SQL query
```

## Advanced usage
Specify which columns to update (all columns are included by default):
```ruby
cat1.name = 'Lilly'
cat1.birthday = '2024-01-01'
cat2.birthday = '2023-06-06'
Cat.batch_update([cat1, cat2], columns: %i[birthday])
```

Ignore model validations (all validations run by default):
```ruby
cat1.name = ''
cat2.name = ''
Cat.batch_update([cat1, cat2], validate: false)
```

Specify a different batch size (100 by default):
```
Cat.batch_update(cats, batch_size: 1000)
```

## License
MIT
