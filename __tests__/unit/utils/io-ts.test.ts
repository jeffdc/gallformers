import { fromEnum, decodeWithDefault } from '../../../libs/utils/io-ts';
import * as E from 'fp-ts/lib/Either';

enum Foo {
    FOO = 'foo',
    BAR = 'bar',
}

const FooSchema = fromEnum('Foo', Foo);

test('fromEnum works', () => {
    expect(FooSchema).toBeTruthy();
    expect(FooSchema.name).toBe('Foo');
    expect(FooSchema.is(Foo.FOO)).toBeTruthy();
    expect(FooSchema.is(Foo.BAR)).toBeTruthy();
    expect(FooSchema.is(null)).toBeFalsy();
    expect(FooSchema.is(true)).toBeFalsy();
    expect(FooSchema.encode(Foo.FOO)).toBe(Foo.FOO);
    expect(E.isRight(FooSchema.decode(Foo.FOO))).toBeTruthy();
    expect(E.isLeft(FooSchema.decode(null))).toBeTruthy();
});

test('decodeWithDefault works', () => {
    expect(decodeWithDefault(E.right(Foo.FOO), Foo.BAR)).toBe(Foo.FOO);
    expect(decodeWithDefault(E.left(Foo.FOO), Foo.BAR)).toBe(Foo.BAR);
});
